class Movie < ActiveRecord::Base
  has_and_belongs_to_many :genres

  collate_group :basic_information, default_open: true do
    collate_on :name, field_transformations: [:downcase, :pizza]
    collate_on :name, operator: :ilike
    collate_on 'genres.id', operator: :contains, field_transformations: [:array_agg], value_transformations: [:join]
    collate_on 'genres.id', operator: :&, not: true, field_transformations: [:array_agg], value_transformations: [:join]
    collate_on :good_movie, operator: :present?
    collate_on :release_date, operator: :ge, field_transformations: [[:date_difference, "date '2017-01-01'"], [:date_part, 'year']]
    collate_on :synopsis, label: 'Keywords', operator: :contains, component: {tags: true}, field_transformations: [:downcase, [:split, ' ']], value_transformations: [:join, :downcase]
  end
end
