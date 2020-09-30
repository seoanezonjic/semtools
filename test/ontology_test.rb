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
class TestOBOFunctionalities < Minitest::Test

	def setup
		# Files
		@file_Header = {file: File.join(AUX_FOLDER, "only_header_sample.obo"), name: "only_header_sample"}
		@file_Hierarchical = {file: File.join(AUX_FOLDER, "hierarchical_sample.obo"), name: "hierarchical_sample"}
		@file_Circular = {file: File.join(AUX_FOLDER, "circular_sample.obo"), name: "circular_sample"}
		@file_Atomic = {file: File.join(AUX_FOLDER, "sparse_sample.obo"), name: "sparse_sample"}
		@file_Sparse = {file: File.join(AUX_FOLDER, "sparse2_sample.obo"), name: "sparse2_sample"}

		## OBO INFO
		@load_Header = [{:file=>File.join(AUX_FOLDER, "only_header_sample.obo"), :name=>"only_header_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{}, :typedefs=>{}, :instances=>{}}]
		@load_Hierarchical_WithoutIndex = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Hierarchical = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}, :Child3=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}, :Child4=>{:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Circular = [{:file=>File.join(AUX_FOLDER, "circular_sample.obo"), :name=>"circular_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All", :is_a=>[:C]}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:B]}}, :typedefs=>{}, :instances=>{}}]
		@load_Atomic = [{:file=>File.join(AUX_FOLDER, "sparse_sample.obo"), :name=>"sparse_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1"}, :Child2=>{:id=>:Child2, :name=>"Child2"}}, :typedefs=>{}, :instances=>{}}]
		@load_Sparse = [{:file=>File.join(AUX_FOLDER, "sparse2_sample.obo"), :name=>"sparse2_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All"}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:A]}, :D=>{:id=>:D, :name=>"Sparsed"}}, :typedefs=>{}, :instances=>{}}]

		# Parentals
		@parentals_Hierachical = [:hierarchical, {:Child1=>[:Parental], :Child2=>[:Parental], :Child3=>[:Parental], :Child4=>[:Parental]}]
		@parentals_Circular = [:circular, {:A=>[:C, :B], :C=>[:B, :A], :B=>[:A, :C]}]
		@parentals_Atomic = [:atomic, {}]
		@parentals_Sparse = [:sparse, {:B=>[:A], :C=>[:A]}]

		# Aux variables
		@basic_tags = {:ancestors => [:is_a], :obsolete => [:is_obsolete], :alternative => [:alt_id,:replaced_by,:consider]}
		@empty_ICs = {:resnick=>{}, :resnick_observed=>{}, :seco=>{}, :zhou=>{}, :sanchez=>{}}
		@erroneous_freq = {:struct_freq=>-1.0, :observed_freq=>-1.0, :max_depth=>-1.0}
		@empty_file = {:file=>nil, :name=>nil}

		# Create necessary instnaces
		@hierarchical = Ontology.new(file: @file_Hierarchical[:file],load_file: true)
		@circular = Ontology.new(file: @file_Circular[:file],load_file: true)
		@atomic = Ontology.new(file: @file_Atomic[:file],load_file: true)
		@sparse = Ontology.new(file: @file_Sparse[:file],load_file: true)

		# Freqs variables
		@hierarchical_freqs_default = {:struct_freq=>2.0, :observed_freq=>-1.0, :max_depth=>2.0}
		@hierarchical_freqs_updated = {:struct_freq=>2.0, :observed_freq=> 2.0, :max_depth=>2.0}
	end

	#################################
	# INIT AND CLASS FUNCTIONALITIES
	#################################

	def test_load_file
		assert_raises Errno::ENOENT do Ontology.load_obo("./.rb") end # Erroneous file path
		assert_equal(@load_Header,Ontology.load_obo(@file_Header[:file])) # Only header
		assert_equal(@load_Hierarchical_WithoutIndex,Ontology.load_obo(@file_Hierarchical[:file])) # Hierarchical
		assert_equal(@load_Circular,Ontology.load_obo(@file_Circular[:file])) # Circular
		assert_equal(@load_Atomic,Ontology.load_obo(@file_Atomic[:file])) # Sparsed
		assert_equal(@load_Sparse,Ontology.load_obo(@file_Sparse[:file])) # Sparsed 2
	end

	def test_expand
		# assert_nil(Ontology.get_related_ids_by_tag(terms: nil,target_tag: "")) # Nil terms
		# assert_nil(Ontology.get_related_ids_by_tag(terms: {},target_tag: "")) # Empty terms
		# assert_nil(Ontology.get_related_ids_by_tag(terms: [],target_tag: "")) # Terms not a hash
		# assert_nil(Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: nil)) # Nil target
		# assert_nil(Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: "")) # No/Empty target
		# assert_nil(Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: 8)) # Target not a string
		# assert_raises ArgumentError do Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: :is_a,split_info_char:" ! ",split_info_indx: -1) end # Erroneous info_indx
		assert_raises TypeError do Ontology.get_related_ids_by_tag(terms: {:A=>[1,2]},target_tag: :is_a) end # Terms without correct format {id, {tags}}
		assert_equal(@parentals_Hierachical,Ontology.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: :is_a)) # Hierarchical structure
		assert_equal(@parentals_Circular,Ontology.get_related_ids_by_tag(terms: @load_Circular[2][:terms],target_tag: :is_a)) # Circular structure
		assert_equal(@parentals_Atomic,Ontology.get_related_ids_by_tag(terms: @load_Atomic[2][:terms],target_tag: :is_a)) # Sparse structure
		assert_equal(@parentals_Sparse,Ontology.get_related_ids_by_tag(terms: @load_Sparse[2][:terms],target_tag: :is_a)) # Sparse structure with some other structures
	end




	#################################
	# SPECIAL TAGS FUNCTIONALITIES
	#################################

	def test_load
		## Check info
		# Header
		assert_equal(@load_Hierarchical[1],@hierarchical.header)
		assert_equal(@load_Circular[1],@circular.header)
		assert_equal(@load_Atomic[1],@atomic.header)		
		assert_equal(@load_Sparse[1],@sparse.header)		
		# Stanzas
		assert_equal(@load_Hierarchical[2],@hierarchical.stanzas)
		assert_equal(@load_Circular[2],@circular.stanzas)
		assert_equal(@load_Atomic[2],@atomic.stanzas)		
		assert_equal(@load_Sparse[2],@sparse.stanzas)		
	end

	def test_obj_parentals
		# Parentals
		@hierarchical.get_index_child_parent_relations # Hierarchical
		@circular.get_index_child_parent_relations # Circular
		@atomic.get_index_child_parent_relations # Atomic
		@sparse.get_index_child_parent_relations # Sparse
	end

	def test_frequencies
		@hierarchical.build_index
		# Check freqs
		assert_equal(@hierarchical_freqs_default,@hierarchical.max_freqs) # Only structural freq
		# Update hierarchical observed freq
		@hierarchical.add_observed_terms(terms: ["Child2","Child2"], transform_to_sym: true)
		# Check observed freq
		assert_equal(@hierarchical_freqs_updated,@hierarchical.max_freqs) # Only structural freq
	end


	def test_ics
		@hierarchical.build_index
		assert_equal(0, @hierarchical.get_IC(:Parental))	# Root
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_IC(:Child2)) # Leaf	
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_IC(:Child1)) # Obsolete
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_IC(:Child3)) # Alternative
	end

	def test_export_import
		# Add extra info to instance
		@hierarchical.build_index
		@hierarchical.get_IC(:Child2)
		# Export object to JSON
		@hierarchical.write(File.join(AUX_FOLDER, "testjson.json"))
		#file: File.join(AUX_FOLDER, "testjson.json"
		obo = Ontology.new()
		obo.read(File.join(AUX_FOLDER, "testjson.json"))
		# Import
		assert_equal(@hierarchical, obo)
		# Remove generated files
		File.delete(File.join(AUX_FOLDER, "testjson.json"))
	end

	#################################
	# METADATA FUNCTIONALITIES
	#################################

	def test_dictionaries
		assert_equal({Parental: ['All'], Child2: ['Child2', 'Child1']}, @hierarchical.calc_dictionary(:name)[:byTerm])
		aux_synonym = {Child2:["1,6-alpha-mannosyltransferase activity"]}
		assert_equal(aux_synonym, @hierarchical.calc_dictionary(:synonym, select_regex: /\"(.*)\"/)[:byTerm])
		assert_equal(:Parental, @hierarchical.translate('All', :name))
		assert_equal(['Child2', "Child1"], @hierarchical.translate(:Child2, :name, byValue: false)) # Official term
		assert_equal(['Child2', "Child1"], @hierarchical.translate(:Child4, :name, byValue: false)) # Alternative term		
		assert_equal('Child2', @hierarchical.translate_id(:Child2))
		assert_equal(:Child2, @hierarchical.translate(aux_synonym[:Child2].first, :synonym, byValue: true))
		assert_equal(:Parental, @hierarchical.translate_name('All'))
		assert_equal(:Child2, @hierarchical.translate_name(aux_synonym[:Child2].first))
		assert_nil(@hierarchical.translate_name("Erroneous name"))
		assert_equal('All', @hierarchical.translate_id(:Parental))
		@hierarchical.calc_dictionary(:name, store_tag: :test)
		assert_equal(@hierarchical.dicts[:name], @hierarchical.dicts[:test])
		assert_equal({"All"=>[:Parental], "Child1"=>[:Child1], "Child2"=>[:Child2, :Child3, :Child4]}, @hierarchical.calc_dictionary(:name, substitute_alternatives: false, multiterm: true)[:byValue])
	end

	def test_familiars_and_valids
		assert_equal([ [:Parental,:Child2], [:FakeID] ], @hierarchical.check_ids([:Parental,:FakeID,:Child3])) # Validate ids
		assert_equal([], @hierarchical.get_ancestors(:Parental)) # Ancestors
		assert_equal([], @hierarchical.get_ancestors(:Parental, true))
		assert_equal([:Parental], @hierarchical.get_ancestors(:Child2))
		assert_equal([:Parental], @hierarchical.get_ancestors(:Child3))
		assert_equal([], @hierarchical.get_descendants(:Child2)) # Descendants
		assert_equal([:Child1, :Child2, :Child3, :Child4], @hierarchical.get_descendants(:Parental))
		assert_equal([:Child2], @hierarchical.get_descendants(:Parental, true))
		assert_equal([[[:Parental, "All"], [[:Child1, "Child2"], [:Child2, "Child2"], [:Child3, "Child2"], [:Child4, "Child2"]]]], @hierarchical.get_childs_table([:Parental])) # Expanded info
		assert_equal([[[:Parental, "All"], [[:Child2,"Child2"]]]], @hierarchical.get_childs_table([:Parental], true))
	end

	def test_similarities
		assert_equal([:Child2,-Math.log10(1.fdiv(2))], @hierarchical.get_MICA(:Child2, :Child2)) # MICA
		assert_equal([:Child2,-Math.log10(1.fdiv(2))], @hierarchical.get_MICA(:Child2, :Child3))
		assert_equal([:Parental,0], @hierarchical.get_MICA(:Child2, :Parental)) # ERR
		assert_equal([:Parental,0], @hierarchical.get_MICA(:Parental, :Parental)) # ERR
		assert_equal(0.0, @hierarchical.get_similarity(:Parental, :Parental)) # SIM
		assert_equal(0.0, @hierarchical.get_similarity(:Parental, :Child2))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_similarity(:Child2, :Child2))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_similarity(:Child2, :Child3))
		profA = [:Child2, :Child3]
		profB = [:Child2]
		profC = [:Parental]
		profD = [:Parental, :Child1]
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profB, profB, bidirectional: false))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profB, profB, bidirectional: true))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profA, profB, bidirectional: false))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profA, profB, bidirectional: true))
		assert_equal(-Math.log10(2.fdiv(2)), @hierarchical.compare(profA, profC, bidirectional: false))
		assert_equal(-Math.log10(2.fdiv(2)), @hierarchical.compare(profA, profC, bidirectional: true))
		sim_D_A = (-Math.log10(2.fdiv(2)) -Math.log10(1.fdiv(2))).fdiv(2)
		sim_A_D = -Math.log10(1.fdiv(2))
		sim_A_D_bi = [sim_A_D, sim_D_A].inject{ |sum, el| sum + el }.to_f / 2
		assert_equal(sim_A_D, @hierarchical.compare(profA, profD, bidirectional: false))
		assert_equal(sim_D_A, @hierarchical.compare(profD, profA, bidirectional: false))
		assert_equal(sim_A_D_bi, @hierarchical.compare(profD, profA, bidirectional: true))
		assert_equal(@hierarchical.compare(profA, profD, bidirectional: true), @hierarchical.compare(profD, profA, bidirectional: true))
		# Store and compare
		@hierarchical.add_profile(:A,profA, substitute: false)
		@hierarchical.add_profile(:D,profD, substitute: false)
		assert_equal(sim_A_D_bi, @hierarchical.compare_profiles[:A][:D])
		assert_equal(-Math.log10(2.fdiv(2)), @hierarchical.compare_profiles(external_profiles: {C: profC})[:A][:C])
	end

	def test_profiles
		@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental, :Child3], substitute: false)
		@hierarchical.add_profile(:D, [:Child3, :Parental, :Child4], substitute: false)
		assert_equal([:Child2, :Parental], @hierarchical.get_profile(:A)) # Check storage
		assert_equal([:Child2, :Parental], @hierarchical.get_profile(:B))
		assert_equal([2, 2, 3, 3], @hierarchical.get_profiles_sizes) # Check metadata
		assert_equal(10.fdiv(4).round(4), @hierarchical.get_profiles_mean_size)
		assert_equal(2, @hierarchical.get_profile_length_at_percentile(0, increasing_sort: true))
		assert_equal(2, @hierarchical.get_profile_length_at_percentile(2.fdiv(4 - 1) * 100, increasing_sort: true))
		assert_equal(3, @hierarchical.get_profile_length_at_percentile(3.fdiv(4 - 1) * 100, increasing_sort: true))
		assert_equal(3, @hierarchical.get_profile_length_at_percentile(4.fdiv(4 - 1) * 100, increasing_sort: true))
		assert_equal(["Child2", "All"], @hierarchical.profile_names(@hierarchical.profiles[:A])) # Profiles to names
		assert_equal([["Child2", "All"], ["Child2", "All"], ["Child2", "All", "Child2"], ["Child2", "All", "Child2"]], @hierarchical.translate_profiles_ids())
		assert_equal({A: ["Child2", "All"], B: ["Child2", "All"], C: ["Child2", "All", "Child2"], D: ["Child2", "All", "Child2"]}, @hierarchical.translate_profiles_ids(asArray: false))
		assert_equal([["Child2", "All"], ["Child2", "All"]], @hierarchical.translate_profiles_ids([@hierarchical.profiles[:A],@hierarchical.profiles[:B]]))
		assert_equal({0 => ["Child2", "All"], 1 => ["Child2", "All"]}, @hierarchical.translate_profiles_ids([@hierarchical.profiles[:A],@hierarchical.profiles[:B]], asArray: false))
		# Frequencies from profiles
		@hierarchical.add_observed_terms_from_profiles
		assert_equal(1, @hierarchical.get_structural_frequency(:Child2)) ## Term by term frequencies
		assert_equal(6, @hierarchical.get_observed_frequency(:Child2))
		assert_equal(1, @hierarchical.get_structural_frequency(:Child3)) # ALternative ID
		assert_equal(6, @hierarchical.get_observed_frequency(:Child3))
		assert_equal(2, @hierarchical.get_structural_frequency(:Parental))
		assert_equal(4, @hierarchical.get_observed_frequency(:Parental))
		assert_equal({Parental: 4.0, Child2: 6.0, Child1: 6.0, Child3: 6.0, Child4: 6.0}, @hierarchical.get_profiles_terms_frequency(literal: false, ratio: false, asArray: false, translate: false)) # Terms frequencies observed
		assert_equal({:Child2=>3, :Parental=>4, :Child3=>2, :Child4=>1}, @hierarchical.get_profiles_terms_frequency(literal: true, ratio: false, asArray: false, translate: false)) # Terms frequencies observed
		assert_equal([[:Child2, 1.5], [:Child1, 1.5], [:Child3, 1.5], [:Child4, 1.5], [:Parental, 1.0]], @hierarchical.get_profiles_terms_frequency(literal: false, ratio: true, asArray: true, translate: false)) 
		assert_equal({:Child2=>3, :Parental=>4, :Child3=>2, :Child4=>1}, @hierarchical.get_profiles_terms_frequency(literal: true, ratio: false, asArray: false, translate: false))
		assert_equal([[:Parental, 1.0], [:Child2, 0.75], [:Child3, 0.5], [:Child4, 0.25]], @hierarchical.get_profiles_terms_frequency(literal: true, ratio: true, asArray: true, translate: false)) 
		# Remove parentals and alternatives
		assert_equal([[:Child2], [:Parental]], @hierarchical.remove_ancestors_from_profile(@hierarchical.profiles[:A]))
		assert_equal([[:Child2, :Child3], [:Parental]], @hierarchical.remove_ancestors_from_profile(@hierarchical.profiles[:C]))
		assert_equal([[:Child2, :Parental], [:Child3]], @hierarchical.remove_alternatives_from_profile(@hierarchical.profiles[:C]))
		assert_equal({A: [:Child2], B: [:Child2], C: [:Child2], D: [:Child3, :Child4]}, @hierarchical.clean_profiles)
		# ICs
		expected_A_IC_resnick = (-Math.log10(1.fdiv(2))-Math.log10(2.fdiv(2))).fdiv(2) 
		assert_equal(expected_A_IC_resnick, @hierarchical.get_profile_mean_IC(@hierarchical.profiles[:A]))
		expected_profiles_IC_resnick = {A: (-Math.log10(1.fdiv(2)) - Math.log10(2.fdiv(2))).fdiv(2),
										B: (-Math.log10(1.fdiv(2)) - Math.log10(2.fdiv(2))).fdiv(2), 
										C: (-Math.log10(1.fdiv(2)) - Math.log10(1.fdiv(2)) - Math.log10(2.fdiv(2))).fdiv(3), 
										D: (-Math.log10(1.fdiv(2)) - Math.log10(1.fdiv(2)) - Math.log10(2.fdiv(2))).fdiv(3)}
		expected_profiles_IC_resnick_observed = {A: (-Math.log10(6.fdiv(6)) - Math.log10(4.fdiv(6))).fdiv(2),
												 B: (-Math.log10(6.fdiv(6)) - Math.log10(4.fdiv(6))).fdiv(2), 
												 C: (-Math.log10(6.fdiv(6)) - Math.log10(4.fdiv(6)) - Math.log10(6.fdiv(6))).fdiv(3), 
												 D: (-Math.log10(6.fdiv(6)) - Math.log10(4.fdiv(6)) - Math.log10(6.fdiv(6))).fdiv(3)}
		assert_equal([expected_profiles_IC_resnick, expected_profiles_IC_resnick_observed], @hierarchical.get_profiles_resnick_dual_ICs)
		# Ontology levels
		assert_equal({1=>[:Parental], 2=>[:Child2, :Child3, :Child4]}, @hierarchical.get_ontology_levels_from_profiles)
		assert_equal({1=>[:Parental, :Parental, :Parental, :Parental], 2=>[:Child2, :Child2, :Child2, :Child3, :Child3, :Child4]}, @hierarchical.get_ontology_levels_from_profiles(false))
		assert_equal({1=>[:Parental], 2=>[:Child2, :Child1, :Child3, :Child4]}, @hierarchical.get_ontology_levels)
		# Profiles dictionary
		@hierarchical.calc_profiles_dictionary
		assert_equal({Child2: [:A, :B, :C], Parental: [:A, :B, :C, :D], Child3: [:C, :D], Child4: [:D]}, @hierarchical.get_terms_linked_profiles)
		# Handle items
		items_rel = {Parental: ['a','b'], Child3: ['c']}
		items_rel_sym = {Parental: [:a, :b], Child3: [:c]}

		@hierarchical.load_item_relations_to_terms(items_rel)
		assert_equal(items_rel, @hierarchical.items)
		@hierarchical.load_item_relations_to_terms(items_rel_sym)
		assert_equal(items_rel_sym, @hierarchical.items)

		# Export/import
		@hierarchical.write(File.join(AUX_FOLDER, "testjson.json"))
		obo = Ontology.new()
		obo.read(File.join(AUX_FOLDER, "testjson.json"))
		assert_equal(@hierarchical, obo)
		File.delete(File.join(AUX_FOLDER, "testjson.json"))
	end

	def test_blacklist
		hierarchical_cutted = Ontology.new(file: @file_Hierarchical[:file],load_file: true, removable_terms: [:Parental])
		assert_equal(0, hierarchical_cutted.meta[:Child2][:ancestors])
		assert_nil(hierarchical_cutted.stanzas[:terms][:Parental])
	end

	def test_term_levels
		hierarchical = Ontology.new(file: @file_Hierarchical[:file],load_file: true)
		assert_equal({:total_paths=>1, :largest_path=>2, :shortest_path=>2, :paths=>[[:Child2, :Parental]]}, hierarchical.term_paths[:Child2])
		assert_equal({1=>[:Parental], 2=>[:Child2, :Child1, :Child3, :Child4]}, hierarchical.get_ontology_levels)
	end

end
