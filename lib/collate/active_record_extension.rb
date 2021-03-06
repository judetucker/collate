require_relative 'filter'
require_relative 'sorter'

module Collate
  module ActiveRecordExtension

    def collate_sort field, opts={}
      initialize_collate

      self.collate_sorters << Collate::Sorter.new(field, opts.merge({base_model_table_name: self.table_name}))
    end

    def collate_on field, opts={}
      initialize_collate

      new_filter = Collate::Filter.new(field, opts.merge({base_model_table_name: self.table_name}))

      self.collate_filters[self.default_group] ||= {filters: []}.merge(self.group_options)
      self.collate_filters[self.default_group][:filters] << new_filter

      if self.default_field_group
        self.collate_field_groups[self.default_group] ||= {filter_groups: {}}.merge(self.group_options)

        self.collate_field_groups[self.default_group][:filter_groups][self.default_field_group] ||= {filters: {}}.merge(self.field_group_options)
        self.collate_field_groups[self.default_group][:filter_groups][self.default_field_group][:filters][new_filter.field_group_type] = new_filter
      end
    end

    def collate_group name, **opts, &blk
      initialize_collate

      opts[:label] ||= name.to_s.titleize
      self.group_options = opts
      self.default_group = name
      blk.call
    end

    def collate_filter_group group_name, **opts, &blk
      initialize_collate

      opts[:label] ||= group_name.to_s.titleize
      self.field_group_options = opts
      self.default_field_group = group_name

      blk.call

      self.default_field_group = nil
    end

    def collate params
      initialize_collate

      ar_rel = self.all

      self.collate_filters.each do |group_key, group|
        group[:filters].each do |filter|
          if params[filter.param_key].present? || params["#{filter.param_key}[]"].present?
            ar_rel = apply_filter(ar_rel, filter, params[filter.param_key] || params["#{filter.param_key}[]"])
          end
        end
      end

      self.collate_sorters.each do |sorter|
        sort_field, _, sort_direction = params[:order].to_s.partition(' ')

        if(sort_field == sorter.field && ['ASC','DESC'].include?(sort_direction))
          ar_rel = apply_sorter ar_rel, sorter, params[:order]
        end
      end

      default_sort = self.collate_sorters.select { |s| s.default }.first
      if default_sort.present?
        ar_rel = apply_sorter ar_rel, default_sort, "#{default_sort.field} #{default_sort.default.upcase}", 'order'
        params[:order] ||= "#{default_sort.field} #{default_sort.default.upcase}"
      end

      ar_rel
    end

  private

    def initialize_collate
      if !self.respond_to? :collate_filters
        class << self
          attr_accessor :collate_filters, :collate_sorters, :default_group,
                        :group_options, :default_field_group, :collate_field_groups,
                        :field_group_options
        end

        self.collate_filters ||= {}
        self.collate_sorters ||= []
        self.default_group ||= :main
        self.group_options ||= {}
        self.collate_field_groups ||= {}
      end
    end

    def apply_sorter ar_rel, sorter, param_value, sorting_method = 'reorder'
      if sorter.joins
        sorter.joins.each do |join|
          ar_rel = ar_rel.joins(join)
        end
      end

      ar_rel = ar_rel.select("#{ar_rel.table_name}.*")

      sorter.field_select = sorter.field unless sorter.field_select

      ar_rel = ar_rel.select(sorter.field_select)

      ar_rel = if sorter.nulls_first
        ar_rel.send(sorting_method, "#{param_value} NULLS FIRST")
      elsif sorter.nulls_last
        ar_rel.send(sorting_method, "#{param_value} NULLS LAST")
      else
        ar_rel.send(sorting_method, param_value)
      end
    end

    def apply_filter ar_rel, filter, param_value
      ar_rel, ar_method, query_string, filter_value = if filter.field.is_a?(Array)
        full_query_strings = []
        full_filter_values = []

        filter.field.each do |filter_field|
          ar_rel, ar_method, query_string, filter_value = get_filter_data ar_rel, filter_field, filter, param_value

          full_query_strings << query_string
          full_filter_values << filter_value
        end

        [ar_rel, ar_method, full_query_strings.join(' OR '), full_filter_values.flatten]
      else
        get_filter_data ar_rel, filter.field.dup, filter, param_value
      end

      ar_rel = if query_string.include?('?')
        if filter.or || filter.field.is_a?(Array)
          ar_rel.send(ar_method, query_string, *filter_value)
        else
          ar_rel.send(ar_method, query_string, filter_value)
        end
      else
        ar_rel.send(ar_method, query_string)
      end
    end

    def get_filter_data ar_rel, filter_field, filter, param_value
      filter_value = if param_value.duplicable?
        param_value.dup
      else
        param_value
      end

      if filter.joins
        filter.joins.each do |join|
          ar_rel = if filter.joins_prefix
            prefix_index = 0
            original_query = ar_rel.model.unscoped.joins(join).to_sql

            previous_replacements = {}
            new_query = original_query.split('INNER JOIN').drop(1).map do |chunk|
              table_name = /([\"'])(?:\\\1|.)*?\1/.match(chunk)[0].gsub('"','')

              if previous_replacements.has_key?("\"#{table_name}\"")
                previous_replacements.delete("\"#{table_name}\"")
                prefix_index += 1

                check_alias_match = /(?<="#{table_name}" ")[^"]*(?=")/.match(chunk)
                if check_alias_match
                  chunk = chunk.partition(check_alias_match[0]).drop(1).join('').prepend('"').gsub(check_alias_match[0], "#{table_name}")
                end
              end

              previous_replacements.each do |the_match, replacement|
                chunk = chunk.gsub(the_match, replacement)
              end

              replaced = chunk.gsub("\"#{table_name}\"", "\"#{filter.joins_prefix[prefix_index]}#{table_name}\"")

              previous_replacements["\"#{table_name}\""] = "\"#{filter.joins_prefix[prefix_index]}#{table_name}\""

              "\"#{table_name}\" AS #{replaced}"
            end.join(' INNER JOIN ').prepend('INNER JOIN ')

            ar_rel.joins(new_query)
          else
            ar_rel.joins(join)
          end
        end
      end

      ar_rel = ar_rel.group(filter.grouping) if filter.grouping

      field_query = filter_field

      filter.field_transformations.each do |ft|
        transformation = ft
        transformation = ft[0] if !transformation.is_a? Symbol
        field_query = case transformation
        when :date_difference
          "age(#{ft[1]}, #{field_query})"
        when :date_part
          "date_part('#{ft[1]}', #{field_query})"
        when :array_agg
          "array_agg(#{field_query})"
        when :downcase
          "lower(#{field_query})"
        when :split
          "string_to_array(#{field_query}, '#{ft[1]}')"
        when :array_length
          "array_length(#{field_query}, '#{ft[1]}')"
        else
          field_query
        end
      end

      if filter.component[:load_records]
        results = filter.component[:load_record_model].constantize.where("#{filter.component[:load_record_field]} IN (?)", filter_value)

        filter.component[:values] = results.map{ |r| {id: r.id, text: r.public_send(filter.component[:load_record_text_method])} }
      end

      if filter.component[:tags]
        filter.component[:values] = filter_value.map { |v| {id: v, text: v} }
      end

      filter.value_transformations.each do |vt|
        transformation = vt
        transformation = vt[0] if !transformation.is_a? Symbol

        filter_value = [filter_value] unless filter.or

        filter_value.each_with_index do |f, i|
          filter_value[i] = case transformation
          when :join
            "#{f.join(vt[1])}"
          when :as_array
            "{#{f}}"
          when :downcase
            f.downcase
          when :string_part
            if vt.is_a? Symbol
              "%#{f}%"
            else
              sprintf vt[1], f
            end
          when :to_json
            "{\"#{vt[1]}\": \"#{f}\"}"
          else
            f
          end
        end
        filter_value = filter_value[0] unless filter.or

      end

      ar_method = filter.having ? "having" : "where"

      query_string = case filter.operator
      when :eq
        "#{field_query} = ?"
      when :ilike
        "#{field_query} ILIKE ?"
      when :in
        "#{field_query} IN (?)"
      when :le
        "#{field_query} <= ?"
      when :ge
        "#{field_query} >= ?"
      when :null
        "#{field_query} IS NULL"
      when :contains
        "#{field_query} @> ?"
      when :present?
        "#{field_query} = true"
      when :&
        "#{field_query} && ?"
      else
        ""
      end

      query_string = filter_value.length.times.collect{query_string}.join(' OR ') if filter.or
      query_string = "NOT(#{query_string})" if filter.not

      [ar_rel, ar_method, query_string, filter_value]
    end

  end
end
