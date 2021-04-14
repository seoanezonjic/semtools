#! /usr/bin/env ruby

BASE_FOLDER = File.dirname(File.expand_path(__FILE__))
$: << File.expand_path(File.join(BASE_FOLDER, '..', 'lib', 'semtools'))
#$: << File.expand_path(File.join(BASE_FOLDER, '../lib'))
AUX_FOLDER = File.join(BASE_FOLDER, 'aux_files')

# require 'test/unit'
require 'minitest/autorun'
require 'ontology'

class TestiEnrichment < Minitest::Test

	def setup
		# Files
		@go_file = File.join(AUX_FOLDER, "partial_go.obo")
		@ontology = Ontology.new(file: @go_file, load_file: true)
	end

	def test_elim
		external_item_list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 20, 21, 22, 23] # Items connected a external factor (A)
		relations =  { #Items connected to ontology factor (B)
		  'GO:0004396'.to_sym => [ 1, 2, 3, 4, 5, 6, 7, 9, 20],
		  #'GO:0016773'.to_sym => [ 1, 2, 3, 4, 8, 21, 22, 23],
		  'GO:0016772'.to_sym => [ 1, 2, 3, 4, 8, 21, 22, 23]
		}
		total_items = 100 # Total items or item universe
		@ontology.load_item_relations_to_terms(relations, remove_old_relations = true)
		pvalues = @ontology.compute_relations_to_items(
			external_item_list, total_items, :elim, 0.01)
		assert_equal(
			[[:"GO:0004396", 3.758742740199465e-10], [:"GO:0016773", 1.0], [:"GO:0016772", 2.5502234633309746e-07]], 
			pvalues)
	end

	def test_weigthed
		external_item_list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 20, 21, 22, 23] # Items connected a external factor (A)
		relations =  { #Items connected to ontology factor (B)
		  'GO:0004396'.to_sym => [ 1, 2, 3, 4, 5, 6, 7, 9, 20],
		  #'GO:0016773'.to_sym => [ 1, 2, 3, 4, 8, 21, 22, 23],
		  'GO:0016772'.to_sym => [ 1, 2, 3, 4, 8, 21, 22, 23]
		}
		total_items = 100 # Total items or item universe
		@ontology.load_item_relations_to_terms(relations, remove_old_relations = true)
		pvalues = @ontology.compute_relations_to_items(
			external_item_list, total_items, :weight, nil)
		assert_equal(
			[[:"GO:0004396", 3.758742740199465e-10], [:"GO:0016773", 2.12513531849739e-07], [:"GO:0016772", 1.4063624541000068e-16]], 
			pvalues)
	end	
end
