#! /usr/bin/env ruby

# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>
# @description class to test Ontology features


#########################################################
# Load necessary packages
#########################################################

BASE_FOLDER = File.dirname(File.expand_path(__FILE__))
$: << File.expand_path(File.join(BASE_FOLDER, '..', 'lib', 'semtools'))
#$: << File.expand_path(File.join(BASE_FOLDER, '../lib'))
AUX_FOLDER = File.join(BASE_FOLDER, 'aux_files')

# require 'test/unit'
require 'minitest/autorun'
require 'ontology'

#########################################################
# Define TESTS
#########################################################
# class TestSimilitudes < Test::Unit::TestCase
class TestJSONparser < Minitest::Test

	def setup
		# Files
		@file_Hierarchical = {file: File.join(AUX_FOLDER, "hierarchical_sample.obo"), name: "hierarchical_sample"}

		# Create necessary instnaces
		@hierarchical = Ontology.new(file: @file_Hierarchical[:file],load_file: true)
	end

	def test_export_import
		# Add extra info to instance
		@hierarchical.precompute
		@hierarchical.get_IC(:Child2)
		# Export object to JSON
		@hierarchical.write(File.join(AUX_FOLDER, "testjson.json"))
		#file: File.join(AUX_FOLDER, "testjson.json"
		obo = Ontology.new()
		JsonParser.load(obo, File.join(AUX_FOLDER, "testjson.json"), build: true)
		assert_equal(@hierarchical, obo)
		# Remove generated files
		File.delete(File.join(AUX_FOLDER, "testjson.json"))
	end

	def test_export_import2
		@hierarchical.write(File.join(AUX_FOLDER, "testjson.json"))
		obo = Ontology.new()
		JsonParser.load(obo, File.join(AUX_FOLDER, "testjson.json"), build: true)
		@hierarchical.precompute
		jsonObo = Ontology.new(file: File.join(AUX_FOLDER, "testjson.json"), load_file: true)
		assert_equal(@hierarchical,jsonObo)
		@hierarchical.get_IC(:Child2)
		obo.get_IC(:Child2)
		assert_equal(@hierarchical, obo)
		# Remove generated files
		File.delete(File.join(AUX_FOLDER, "testjson.json"))
	end

end
