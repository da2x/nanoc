# frozen_string_literal: true

require_relative 'support/item_rep_collection_view_examples'

describe Nanoc::BasicItemRepCollectionView do
  let(:expected_view_class) { Nanoc::BasicItemRepView }

  it_behaves_like 'an item rep collection view'
end
