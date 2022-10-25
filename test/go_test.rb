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
class TestGO < Minitest::Test

    def test_go_export_import
        @go = Ontology.new(file: File.join(AUX_FOLDER, "go-basic_sample.obo"), load_file: true)
        # Export object to JSON
        @go.write(File.join(AUX_FOLDER, "gotestjson.json"))
        obo = Ontology.new(file: File.join(AUX_FOLDER, "gotestjson.json"), load_file: true)
        assert_equal(@go, obo)
        # Remove generated files
        File.delete(File.join(AUX_FOLDER, "gotestjson.json"))
    end

    def test_go_export_import_several_records
        @go = Ontology.new(file: File.join(AUX_FOLDER, "partial_go.obo"), load_file: true)
        # Export object to JSON
        @go.write(File.join(AUX_FOLDER, "gotestjsonFull.json"))
        #file: File.join(AUX_FOLDER, "testjson.json"
        obo = Ontology.new(file: File.join(AUX_FOLDER, "gotestjsonFull.json"), load_file: true)
        assert_equal(@go, obo)
        # Remove generated files
        File.delete(File.join(AUX_FOLDER, "gotestjsonFull.json"))
    end

    def test_go_several_records_compare_structure
        @go = Ontology.new(file: File.join(AUX_FOLDER, "partial_go.obo"), load_file: true)
        # Export object to JSON
        #@go.write(File.join(AUX_FOLDER, "partial_go.json"))
        #file: File.join(AUX_FOLDER, "testjson.json"
        
        obo = Ontology.new(file: File.join(AUX_FOLDER, "partial_go.json"), load_file: true)
        assert_equal(@go, obo)
        # Remove generated files
        #File.delete(File.join(AUX_FOLDER, "gotestjsonFull.json"))
    end



end
