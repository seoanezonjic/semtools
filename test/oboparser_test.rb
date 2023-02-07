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
class TestOBOparser < Minitest::Test

	def setup
		# Files
		@file_Header = {file: File.join(AUX_FOLDER, "only_header_sample.obo"), name: "only_header_sample"}
		@file_Hierarchical = {file: File.join(AUX_FOLDER, "hierarchical_sample.obo"), name: "hierarchical_sample"}
		@file_Circular = {file: File.join(AUX_FOLDER, "circular_sample.obo"), name: "circular_sample"}
		@file_Atomic = {file: File.join(AUX_FOLDER, "sparse_sample.obo"), name: "sparse_sample"}
		@file_Sparse = {file: File.join(AUX_FOLDER, "sparse2_sample.obo"), name: "sparse2_sample"}
		@file_SH = File.join(AUX_FOLDER, "short_hierarchical_sample.obo")
		@file_Enr = File.join(AUX_FOLDER, "enrichment_ontology.obo")

		## OBO INFO
		@load_Header = [{:file=>File.join(AUX_FOLDER, "only_header_sample.obo"), :name=>"only_header_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{}, :typedefs=>{}, :instances=>{}}]
		@load_Hierarchical_WithoutIndex =[
			{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, 
			{:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, 
			{:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, 
			:Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, 
			:Child2=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}, 
			:Child5=>{:id=>:Child5, :name=>"Child5", :synonym=>["\"activity related to example\" EXACT []"], :is_obsolete=>"true", :is_a=>[:Parental]}
			}, 
			:typedefs=>{}, :instances=>{}}]
		@load_Hierarchical_altid = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, 
			{:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, 
			:Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, 
			:Child2=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]},
			:Child3=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}, 
			:Child4=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]},
			:Child5=>{:id=>:Child5, :name=>"Child5", :synonym=>["\"activity related to example\" EXACT []"], :is_obsolete=>"true", :is_a=>[:Parental]}}, 
			:typedefs=>{}, :instances=>{}}]
		@load_Hierarchical = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"},
		{:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, 
		:Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete=>"true", :is_a=>[:Parental], :replaced_by=>[:Child2]}, 
		:Child2=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}, 
		:Child5=>{:id=>:Child5, :name=>"Child5", :synonym=>["\"activity related to example\" EXACT []"], :is_obsolete=>"true", :is_a=>[:Parental]}},
		:typedefs=>{}, :instances=>{}}]
		@load_Circular = [{:file=>File.join(AUX_FOLDER, "circular_sample.obo"), :name=>"circular_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All", :is_a=>[:C]}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:B]}}, :typedefs=>{}, :instances=>{}}]
		@load_Atomic = [{:file=>File.join(AUX_FOLDER, "sparse_sample.obo"), :name=>"sparse_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1"}, :Child2=>{:id=>:Child2, :name=>"Child2"}}, :typedefs=>{}, :instances=>{}}]
		@load_Sparse = [{:file=>File.join(AUX_FOLDER, "sparse2_sample.obo"), :name=>"sparse2_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All"}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:A]}, :D=>{:id=>:D, :name=>"Sparsed"}}, :typedefs=>{}, :instances=>{}}]

		## OBO INFO2
		@load_Hierarchical_WithoutIndex2 = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Hierarchical2 = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}, :Child3=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}, :Child4=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Circular2 = [{:file=>File.join(AUX_FOLDER, "circular_sample.obo"), :name=>"circular_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All", :is_a=>[:C]}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:B]}}, :typedefs=>{}, :instances=>{}}]

		@hierarchical_terms2 = {Child2: {is_a: [:B]}, Parental: {is_a: [:A]}}

		# Parentals
		@parentals_Hierachical = [:hierarchical, {:Child1=>[:Parental], :Child2=>[:Parental], :Child3=>[:Parental], :Child4=>[:Parental], :Child5=>[:Parental]}]
		@parentals_Circular = [:circular, {:A=>[:C, :B], :C=>[:B, :A], :B=>[:A, :C]}]
		@parentals_Atomic = [:atomic, {}]
		@parentals_Sparse = [:sparse, {:B=>[:A], :C=>[:A]}]

	end

	def test_load_file
		assert_raises Errno::ENOENT do OboParser.load_obo("./.rb") end # Erroneous file path
		assert_equal(@load_Header,OboParser.load_obo(@file_Header[:file])) # Only header
		assert_equal(@load_Hierarchical_WithoutIndex,OboParser.load_obo(@file_Hierarchical[:file])) # Hierarchical
		assert_equal(@load_Circular,OboParser.load_obo(@file_Circular[:file])) # Circular
		assert_equal(@load_Atomic,OboParser.load_obo(@file_Atomic[:file])) # Sparsed
		assert_equal(@load_Sparse,OboParser.load_obo(@file_Sparse[:file])) # Sparsed 2
	end

	def test_expand
		# assert_nil(Ontology.get_related_ids_by_tag(terms: nil,target_tag: "")) # Nil terms
		# assert_nil(Ontology.get_related_ids_by_tag(terms: {},target_tag: "")) # Empty terms
		# assert_nil(Ontology.get_related_ids_by_tag(terms: [],target_tag: "")) # Terms not a hash
		# assert_nil(Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: nil)) # Nil target
		# assert_nil(Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: "")) # No/Empty target
		# assert_nil(Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: 8)) # Target not a string
		# assert_raises ArgumentError do Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: :is_a,split_info_char:" ! ",split_info_indx: -1) end # Erroneous info_indx
		assert_raises TypeError do OboParser.get_related_ids_by_tag(terms: {:A=>[1,2]},target_tag: :is_a) end # Terms without correct format {id, {tags}}
		assert_equal(@parentals_Hierachical,OboParser.get_related_ids_by_tag(terms: @load_Hierarchical_altid[2][:terms],target_tag: :is_a)) # Hierarchical structure
		assert_equal(@parentals_Circular,OboParser.get_related_ids_by_tag(terms: @load_Circular[2][:terms],target_tag: :is_a)) # Circular structure
		assert_equal(@parentals_Atomic,OboParser.get_related_ids_by_tag(terms: @load_Atomic[2][:terms],target_tag: :is_a)) # Sparse structure
		assert_equal(@parentals_Sparse,OboParser.get_related_ids_by_tag(terms: @load_Sparse[2][:terms],target_tag: :is_a)) # Sparse structure with some other structures
	end

	def test_expand2
		# Test regular
		assert_equal([:hierarchical,[:Parental]], OboParser.get_related_ids(:Child2, @load_Hierarchical2[2][:terms], :is_a))
		# Test with already expanded info
		aux_expansion = {Parental: [:A]}
		assert_equal([:hierarchical,[:Parental, :A]], OboParser.get_related_ids(:Child2, @load_Hierarchical2[2][:terms], :is_a, aux_expansion))		
		# Test circular
		assert_equal([:circular,[:C,:B]], OboParser.get_related_ids(:A, @load_Circular2[2][:terms], :is_a))
		assert_equal([:circular,[:B,:A]], OboParser.get_related_ids(:C, @load_Circular2[2][:terms], :is_a))
	end

	def test_load
		_, header, stanzas = OboParser.load_obo(@file_Hierarchical[:file])
		assert_equal(@load_Hierarchical[1], header)
		assert_equal(@load_Hierarchical[2], stanzas)

		_, header, stanzas = OboParser.load_obo(@file_Circular[:file])
		assert_equal(@load_Circular[1], header)
		assert_equal(@load_Circular[2], stanzas)

		_, header, stanzas = OboParser.load_obo(@file_Atomic[:file])
		assert_equal(@load_Atomic[1], header)		
		assert_equal(@load_Atomic[2], stanzas)		

		_, header, stanzas = OboParser.load_obo(@file_Sparse[:file])
		assert_equal(@load_Sparse[1], header)		
		assert_equal(@load_Sparse[2], stanzas)
	end

	def test_dictionaries
		OboParser.load(Ontology.new(), @file_Hierarchical[:file], build: true)
		names_dict = OboParser.calc_dictionary(:name)
		assert_equal({Parental: ['All'], Child2: ['Child2']}, names_dict[:byTerm])
		test_dict = OboParser.calc_dictionary(:name, store_tag: :test)
		assert_equal(names_dict, test_dict)
		aux_synonym = {Child2:["1,6-alpha-mannosyltransferase activity"]}
		assert_equal(aux_synonym, OboParser.calc_dictionary(:synonym, select_regex: /\"(.*)\"/)[:byTerm])
		assert_equal({"All"=>[:Parental], "Child2"=>[:Child2]}, OboParser.calc_dictionary(:name, multiterm: true)[:byValue])
	end

	def test_blacklist
		hierarchical_cutted = Ontology.new(file: @file_Hierarchical[:file],load_file: true, removable_terms: [:Parental])
		assert_equal(0, hierarchical_cutted.meta[:Child2][:ancestors])
		assert_nil(hierarchical_cutted.terms[:Parental])
	end
end
