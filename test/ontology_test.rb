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
		@file_SH = {file: File.join(AUX_FOLDER, "short_hierarchical_sample.obo"), name: "short_hierarchical_sample"}
		@file_Enr = {file: File.join(AUX_FOLDER, "enrichment_ontology.obo"), name: "enrichment_ontology"}

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
		@empty_ICs = {:resnik=>{}, :resnik_observed=>{}, :seco=>{}, :zhou=>{}, :sanchez=>{}}
		@erroneous_freq = {:struct_freq=>-1.0, :observed_freq=>-1.0, :max_depth=>-1.0}
		@empty_file = {:file=>nil, :name=>nil}

		# Create necessary instnaces
		@hierarchical = Ontology.new(file: @file_Hierarchical[:file],load_file: true)
		@short_hierarchical = Ontology.new(file: @file_SH[:file], load_file: true)
		@enrichment_hierarchical = Ontology.new(file: @file_Enr[:file], load_file: true)
		@circular = Ontology.new(file: @file_Circular[:file],load_file: true)
		@atomic = Ontology.new(file: @file_Atomic[:file],load_file: true)
		@sparse = Ontology.new(file: @file_Sparse[:file],load_file: true)

		# Freqs variables
		@hierarchical_freqs_default = {:struct_freq=>2.0, :observed_freq=>-1.0, :max_depth=>2.0}
		@hierarchical_freqs_updated = {:struct_freq=>2.0, :observed_freq=> 3.0, :max_depth=>2.0}
	end

	#################################
	# IO JSON
	#################################

	def test_export_import
		# Export/import
		@hierarchical.write(File.join(AUX_FOLDER, "testjson.json"))
		obo = Ontology.new(file: File.join(AUX_FOLDER, "testjson.json"), build: false )
		assert_equal(@hierarchical, obo)
		File.delete(File.join(AUX_FOLDER, "testjson.json"))
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

	#################################
    # GENERATE METADATA FOR ALL ITEMS
	#################################

	def test_generate_metadata_for_all_items
		@hierarchical.precompute
		# Check freqs
		assert_equal({:Parental=>{:ancestors=>0.0, :descendants=>1.0, :struct_freq=>2.0, :observed_freq=>0.0},
					  :Child2=>{:ancestors=>1.0, :descendants=>0.0, :struct_freq=>1.0, :observed_freq=>0.0}},
					   @hierarchical.meta)
		assert_equal(@hierarchical_freqs_default,@hierarchical.max_freqs) # Only structural freq
	end

	def test_paths_levels
		@hierarchical.expand_path(:Child2)
		default_child2_paths = {:total_paths=>1, :largest_path=>2, :shortest_path=>2, :paths=>[[:Child2, :Parental]]}
		assert_equal(default_child2_paths, @hierarchical.term_paths[:Child2])

		@hierarchical.calc_term_levels(calc_paths: true, shortest_path: true)
		## Testing levels
		# For all terms
		default_levels = {:byTerm=>{1=>[:Parental], 2=>[:Child2]}, :byValue=>{:Parental=>1, :Child2=>2}}
		assert_equal(default_levels, @hierarchical.dicts[:level])
		## Testing paths
		default_paths = {:Parental=>{:total_paths=>1, :largest_path=>1, :shortest_path=>1, :paths=> [[:Parental]]}, 
		:Child2=>{:total_paths=>1, :largest_path=>2, :shortest_path=>2, :paths=>[[:Child2, :Parental]]}}
		assert_equal(default_paths,@hierarchical.term_paths) 

		child2_parental_path = [:Parental]
		assert_equal(child2_parental_path,@hierarchical.get_parental_path(:Child2, which_path = :shortest_path))

		# assert_equal({1=>[:Parental], 2=>[:Child2]}, @hierarchical.get_ontology_levels) # FRED: redundant test?
	end


	#################################
	# TERM METHODS
	#################################

	# I/O observed term from data
    ####################################

    def test_add_observed_terms
    	@hierarchical.add_observed_terms(terms: ["Parental"], transform_to_sym: true)
    	@hierarchical.add_observed_terms(terms: ["Child2","Child2"], transform_to_sym: true)
		
		assert_equal(@hierarchical_freqs_updated,@hierarchical.max_freqs) 
		assert_equal({:ancestors=>1.0, :descendants=>0.0, :struct_freq=>1.0, :observed_freq=>2.0},
			@hierarchical.meta[:Child2])
		assert_equal({:ancestors=>0.0, :descendants=>1.0, :struct_freq=>2.0, :observed_freq=>3.0},
			@hierarchical.meta[:Parental])
    end

    # Obtain level and term relations
    ####################################

    def test_level_term_relations
    	assert_equal([], @hierarchical.get_ancestors(:Parental)) # Ancestors
		assert_equal([:Parental], @hierarchical.get_ancestors(:Child2))
		assert_equal([], @hierarchical.get_descendants(:Child2)) # Descendants
		assert_equal([:Child2], @hierarchical.get_descendants(:Parental))
		assert_nil(@hierarchical.get_direct_descendants(:Child1))
		assert_equal([:Child2], @hierarchical.get_direct_descendants(:Parental))
    end

    # ID Handlers
    ####################################

    def test_id_handlers
		# Translate Terms
		aux_synonym = {Child2:["1,6-alpha-mannosyltransferase activity"]}
		assert_equal(:Parental, @hierarchical.translate('All', :name))
		assert_equal(['Child2'], @hierarchical.translate(:Child2, :name, byValue: false)) # Official term
		assert_equal('Child2', @hierarchical.translate_id(:Child2))
		assert_equal(:Child2, @hierarchical.translate(aux_synonym[:Child2].first, :synonym, byValue: true))
		assert_equal(:Parental, @hierarchical.translate_name('All'))
		assert_equal(:Child2, @hierarchical.translate_name(aux_synonym[:Child2].first))
		assert_nil(@hierarchical.translate_name("Erroneous name"))
		assert_equal('All', @hierarchical.translate_id(:Parental))
		assert_equal(:Child2, @hierarchical.get_main_id(:Child1))
    end

	# Get term frequency and information
    ####################################

    def test_ics
		@hierarchical.precompute
		assert_equal(0, @hierarchical.get_IC(:Parental))	# Root
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_IC(:Child2)) # Leaf	
    end

	def test_similarities
		@hierarchical.add_observed_terms(terms: ["Child2","Child2","Child2","Parental","Parental","Parental","Parental"], transform_to_sym: true)
		assert_equal(1, @hierarchical.get_structural_frequency(:Child2)) ## Term by term frequencies
		assert_equal(3, @hierarchical.get_observed_frequency(:Child2))
		assert_equal(2, @hierarchical.get_structural_frequency(:Parental))
		assert_equal(7, @hierarchical.get_observed_frequency(:Parental))


		assert_equal([:Child2,-Math.log10(1.fdiv(2))], @hierarchical.get_MICA(:Child2, :Child2)) # MICA
		assert_equal(-Math.log10(3.fdiv(5)), @enrichment_hierarchical.get_ICMICA(:branchAChild1,:branchAChild2)) #ICMICA
		assert_equal(0, @enrichment_hierarchical.get_ICMICA(:branchAChild1,:branchB)) #ICMICA
		assert_nil(@sparse.get_ICMICA(:B,:D)) #ICMICA
		assert_equal([:Parental,0], @hierarchical.get_MICA(:Child2, :Parental)) # ERR
		assert_equal([:Parental,0], @hierarchical.get_MICA(:Parental, :Parental)) # ERR
		assert_equal(0.0, @hierarchical.get_similarity(:Parental, :Parental)) # SIM
		assert_equal(0.0, @hierarchical.get_similarity(:Parental, :Child2))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_similarity(:Child2, :Child2))
	end

    # Checking valid terms
    ####################################

    def test_valid_terms
		assert_equal(false, @hierarchical.term_exist?(:FakeID)) # Validate ids
		assert_equal(true, @hierarchical.term_exist?(:Parental)) # Validate ids
		assert_equal(false, @hierarchical.is_obsolete?(:Child2)) # Validate ids
		assert_equal(true, @hierarchical.is_obsolete?(:Child1)) # Validate ids
    end

	#############################################
    # PROFILE EXTERNAL METHODS
    #############################################

    # Modifying Profile
    ####################################

    def test_modifiying_profile_externel
    	# Remove by scores
		prof = [:Parental,:Child2]
		scores = {Parental: 3, Child2: 7}
		assert_equal([:Child2],@hierarchical.clean_profile_by_score(prof,scores, byMax: true))
		assert_equal([:Parental],@hierarchical.clean_profile_by_score(prof,scores, byMax: false))
		scores2 = {Child2: 7}
		assert_equal([:Child2],@hierarchical.clean_profile_by_score(prof,scores2, byMax: true))
		assert_equal([:Child2],@hierarchical.clean_profile_by_score(prof,scores2, byMax: false))
		prof2 = [:Parental,:Child3]
		# Child 3 is not into scores, it will remove it
		assert_equal([:Parental],@hierarchical.clean_profile_by_score(prof2,scores, byMax: true))
		assert_equal([:Parental],@hierarchical.clean_profile_by_score(prof2,scores, byMax: false))
		assert_equal([:Parental,:Child3],@hierarchical.clean_profile_by_score(prof2,scores, byMax: false, remove_without_score: false))

		assert_equal([:Child2],@hierarchical.clean_profile_hard([:Child2, :Parental, :Child5, :Child1]))
		assert_equal([:branchAChild1,:branchAChild2],@enrichment_hierarchical.clean_profile_hard([:root, :branchB,:branchAChild1,:branchAChild2], options = {:term_filter => :branchA})) # Testing term_filter option
		
		# Remove parentals and alternatives
		assert_equal([[:Child2], [:Parental]], @hierarchical.remove_ancestors_from_profile([:Child2, :Parental]))
		assert_equal([[:Child2, :Parental], [:Child3]], @hierarchical.remove_alternatives_from_profile([:Child2, :Parental, :Child3]))

		# Expand parental 
		## For one profile
		assert_equal([:branchA, :root, :branchAChild1, :branchB] , @enrichment_hierarchical.expand_profile_with_parents([:branchAChild1, :branchB])) 
    end

    # ID Handlers
    #################################### 

    def test_id_handlers_external
		assert_equal([ [:Parental,:Child2], [:FakeID] ], @hierarchical.check_ids([:Parental,:FakeID,:Child3])) # Validate ids
		assert_equal([["All", "Child2", "Child5"], [nil]], @enrichment_hierarchical.translate_ids([:root,:branchAChild3, :branchB, :FakeID]))
		assert_equal([[:root, :branchAChild1, :branchB], ["FakeName"]], @enrichment_hierarchical.translate_names(["All", "Child2", "Child5","FakeName"]))
    end

    # Description of profile's terms
    ####################################

    def test_description_profile_terms
		assert_equal([[[:Parental, "All"], [[:Child2, "Child2"]]]], @hierarchical.get_childs_table([:Parental])) # Expanded info
		# For a profile
		assert_equal([[:Child2, 2], [:Child1, nil], [:Parental, 1]],@hierarchical.get_terms_levels([:Child2,:Child1,:Parental]))
    end


    # IC data
    ####################################

    def test_ic_profile_external
    	expected_A_IC_resnik = (-Math.log10(1.fdiv(2))-Math.log10(2.fdiv(2))).fdiv(2)
		assert_equal(expected_A_IC_resnik, @hierarchical.get_profile_mean_IC([:Child2, :Parental]))
		assert_equal([:branchA, -Math.log10(3.fdiv(5))],@enrichment_hierarchical.get_maxmica_term2profile(:branchA,[:branchAChild1,:branchB]))
    end

    def test_similarities_profile_external
		profA = [:Child2]
		profB = [:Child2]
		profC = [:Parental]
		profD = [:Parental, :Child2]
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profB, profB, bidirectional: false))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profB, profB, bidirectional: true))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profA, profB, bidirectional: false))
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.compare(profA, profB, bidirectional: true))
		assert_equal(-Math.log10(2.fdiv(2)), @hierarchical.compare(profA, profC, bidirectional: false))
		assert_equal(-Math.log10(2.fdiv(2)), @hierarchical.compare(profA, profC, bidirectional: true))
		sim_D_A = (-Math.log10(2.fdiv(2)) -Math.log10(1.fdiv(2))).fdiv(2)
		sim_A_D = -Math.log10(1.fdiv(2))
		sim_A_D_bi = (sim_D_A * 2 + sim_A_D).to_f / 3
		assert_equal(sim_A_D, @hierarchical.compare(profA, profD, bidirectional: false))
		assert_equal(sim_D_A, @hierarchical.compare(profD, profA, bidirectional: false))
		assert_equal(sim_A_D_bi, @hierarchical.compare(profD, profA, bidirectional: true))
		assert_equal(@hierarchical.compare(profA, profD, bidirectional: true), @hierarchical.compare(profD, profA, bidirectional: true))
    end

    #############################################
    # PROFILE INTERNAL METHODS 
    #############################################

    # I/O profiles
    ####################################

    def test_io_profiles_internal
    	# loading profiles
		@hierarchical.load_profiles({:A => [:Child1, :Parental], :B => [:Child3, :Child4, :Parental, :FakeID],:C => [:Child2, :Parental], :D => [:Parental]}, calc_metadata: false, substitute: false)
		assert_equal({:A=>[:Child1, :Parental], :B=>[:Child3, :Child4, :Parental], :C=>[:Child2, :Parental], :D=>[:Parental]}, @hierarchical.profiles)
		#@hierarchical.load_profiles({:A => [:Child1, :Parental], :B => [:Child3, :Child4, :Parental, :FakeID],:C => [:Child2, :Parental], :D => [:Parental]}, substitute: true)
		#assert_equal({:A=>[:Child2, :Parental], :B=>[:Child2, :Parental], :C=>[:Child2, :Parental], :D=>[:Parental]}, @hierarchical.profiles) # FRED: Shouldn´t this return uniq ids?
		@hierarchical.reset_profiles()
		assert_equal({}, @hierarchical.profiles)
		@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental], substitute: false)
		@hierarchical.add_profile(:D, [:Parental], substitute: false)
		assert_equal([:Child2, :Parental], @hierarchical.get_profile(:A)) # Check storage
		assert_equal([:Child2, :Parental], @hierarchical.get_profile(:B))

    end

    # Modifying profiles
    ####################################

    def test_modifying_profile_internal
    	@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental], substitute: false)
		@hierarchical.add_profile(:D, [:Parental], substitute: false)
		# Expand parental 
		## Parental method for @profiles
		@enrichment_hierarchical.load_profiles({:A => [:branchAChild1, :branchB],
			:B => [:branchAChild2, :branchA,:branchB],
			:C => [:root, :branchAChild2, :branchAChild1],
			:D => [:FakeID]},
			 calc_metadata: false, substitute: false)
		@enrichment_hierarchical.expand_profiles('parental') # FRED: Maybe we could add "propagate" version but this is checked in test_expand_items
		assert_equal({:A=>[:branchA, :root, :branchAChild1, :branchB], :B=>[:branchA, :root, :branchAChild2, :branchB], :C=>[:branchA, :root, :branchAChild2, :branchAChild1], :D=>[]},@enrichment_hierarchical.profiles)
		@enrichment_hierarchical.reset_profiles()
		assert_equal({A: [:Child2], B: [:Child2], C: [:Child2], D: [:Parental]}, @hierarchical.clean_profiles)
    end

    # ID Handlers
    ####################################

    def test_id_handlers_internal
    	@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental], substitute: false)
		@hierarchical.add_profile(:D, [:Parental], substitute: false)

    	# Translators
		assert_equal([["Child2", "All"], ["Child2", "All"], ["Child2", "All"], ["All"]], @hierarchical.translate_profiles_ids())
		assert_equal({A: ["Child2", "All"], B: ["Child2", "All"], C: ["Child2", "All"], D: ["All"]}, @hierarchical.translate_profiles_ids(asArray: false))
		test_profiles = [@hierarchical.profiles[:A],@hierarchical.profiles[:B]]
		assert_equal([["Child2", "All"], ["Child2", "All"]], @hierarchical.translate_profiles_ids(test_profiles))
		assert_equal({0 => ["Child2", "All"], 1 => ["Child2", "All"]}, @hierarchical.translate_profiles_ids(test_profiles, asArray: false))

    end

    # Description of profile size
    ####################################

    def test_description_profile_size

    	@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental], substitute: false)
		@hierarchical.add_profile(:D, [:Parental], substitute: false)

		# Getiings
		assert_equal([2, 2, 2, 1], @hierarchical.get_profiles_sizes) # Check metadata
		assert_equal(7.fdiv(4).round(4), @hierarchical.get_profiles_mean_size)
		assert_equal({:average=>1.75, 
					  :variance=>3.25,
					  :standardDeviation=>Math.sqrt(3.25), 
					  :max=>2, :min=>1, :count=>4, :countNonZero=>4, 
					  :q1=>1.5, :median=>2.0, :q3=>2.0}, @hierarchical.profile_stats)
		assert_equal(1, @hierarchical.get_profile_length_at_percentile(0, increasing_sort: true))
		assert_equal(2, @hierarchical.get_profile_length_at_percentile(2.fdiv(4 - 1) * 100, increasing_sort: true))
		assert_equal(2, @hierarchical.get_profile_length_at_percentile(3.fdiv(4 - 1) * 100, increasing_sort: true))
		assert_equal(2, @hierarchical.get_profile_length_at_percentile(4.fdiv(4 - 1) * 100, increasing_sort: true))

    end

    # IC data
    ####################################

    def test_similarities_profile_internal
		@hierarchical.add_profile(:A,[:Child2], substitute: false)
		@hierarchical.add_profile(:D,[:Parental,:Child2], substitute: false)
		sim_D_A = (-Math.log10(2.fdiv(2)) -Math.log10(1.fdiv(2))).fdiv(2)
		sim_A_D = -Math.log10(1.fdiv(2))
		sim_A_D_bi = (sim_D_A * 2 + sim_A_D).to_f / 3
		assert_equal(sim_A_D_bi, @hierarchical.compare_profiles[:A][:D])
		assert_equal(-Math.log10(2.fdiv(2)), @hierarchical.compare_profiles(external_profiles: {C: [:Parental]})[:A][:C])
		@hierarchical.add_observed_terms_from_profiles()
		assert_equal([{:Child2=>-Math.log10(0.5), :Parental=>-Math.log10(1)}, {:Child2=>-Math.log10(2.fdiv(3)), :Parental=>-Math.log10(1)}],@hierarchical.get_observed_ics_by_onto_and_freq())
    end

	def test_ic_profile_internal
		@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental], substitute: false)
		@hierarchical.add_profile(:D, [:Parental], substitute: false)

		# Frequencies from profiles
		@hierarchical.add_observed_terms_from_profiles
		assert_equal({:Child2=>3, :Parental=>4}, @hierarchical.get_profiles_terms_frequency(ratio: false, asArray: false, translate: false)) # Terms frequencies observed
		assert_equal([[:Parental, 1.0], [:Child2, 0.75]], @hierarchical.get_profiles_terms_frequency(ratio: true, asArray: true, translate: false)) 
		assert_equal({:Child2=>3, :Parental=>4}, @hierarchical.get_profiles_terms_frequency(ratio: false, asArray: false, translate: false))
		assert_equal([[:Parental, 1.0], [:Child2, 0.75]], @hierarchical.get_profiles_terms_frequency(ratio: true, asArray: true, translate: false)) 

		# ICs
		expected_profiles_IC_resnik = {A: (-Math.log10(1.fdiv(2)) - Math.log10(2.fdiv(2))).fdiv(2),
										B: (-Math.log10(1.fdiv(2)) - Math.log10(2.fdiv(2))).fdiv(2), 
										C: (-Math.log10(1.fdiv(2)) - Math.log10(2.fdiv(2))).fdiv(2), 
										D: 0.0 }
		expected_profiles_IC_resnik_observed = {A: (-Math.log10(3.fdiv(7)) - Math.log10(7.fdiv(7))).fdiv(2),
												 B: (-Math.log10(3.fdiv(7)) - Math.log10(7.fdiv(7))).fdiv(2), 
												 C: (-Math.log10(3.fdiv(7)) - Math.log10(7.fdiv(7))).fdiv(2), 
												 D: 0.0 }
		assert_equal([expected_profiles_IC_resnik, expected_profiles_IC_resnik_observed], @hierarchical.get_profiles_resnik_dual_ICs)
	end


    # specifity_index related methods
    ####################################

	def test_onto_levels_from_profiles
		@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental], substitute: false)
		@hierarchical.add_profile(:D, [:Parental], substitute: false)
 
		# Ontology levels
		assert_equal({1=>[:Parental], 2=>[:Child2]}, @hierarchical.get_ontology_levels_from_profiles)
		assert_equal({1=>[:Parental, :Parental, :Parental, :Parental], 2=>[:Child2, :Child2, :Child2]}, @hierarchical.get_ontology_levels_from_profiles(false))
		assert_equal({1=>[:Parental], 2=>[:Child2]}, @hierarchical.get_ontology_levels)
	end

    def test_specificity_index
		@hierarchical.load_profiles({:A => [:Child2], :B => [:Parental],:C => [:Child2, :Parental]}, calc_metadata: false, substitute: false)
		assert_equal([[[1, 1, 2], [2, 1, 2]], [[1, 50.0, 50.0, 50.0], [2, 50.0, 50.0, 50.0]]] ,@hierarchical.get_profile_ontology_distribution_tables)
		assert_equal(0.967, @hierarchical.get_weigthed_level_contribution([[1,0.5],[2,0.7]],3,3).round(3))
		
		enrichment_hierarchical2 = Ontology.new(file:File.join(AUX_FOLDER, "enrichment_ontology2.obo"), load_file: true)
		enrichment_hierarchical2.load_profiles({:A => [:branchB,:branchAChild1,:root],
			:B => [:root,:branchA,:branchB,:branchAChild2,:branchAChild1],
			:C => [:root,:branchC, :branchAChild1,:branchAChild2],
			:D => [:root,:branchAChild1, :branchAChild2]},
			 calc_metadata: false, substitute: false)
		assert_equal(13.334.fdiv(10).round(4),enrichment_hierarchical2.get_dataset_specifity_index('weigthed').round(4))
		assert_equal(0,enrichment_hierarchical2.get_dataset_specifity_index('uniq'))
    end

    ########################################
    ## GENERAL ONTOLOGY METHODS
    ########################################

    def test_IO_items
    	# Handle items
		items_rel = {Parental: ['a','b'], Child3: ['c']}
		items_rel_sym = {Parental: [:a, :b], Child3: [:c]}
		items_rel_concat = {Parental: [:a,:b,'a','b'], Child3: [:c,'c']}

		@hierarchical.items = {} # reset items from method get_items_from_profiles
		@hierarchical.load_item_relations_to_terms(items_rel)
		assert_equal(items_rel, @hierarchical.items)
		@hierarchical.load_item_relations_to_terms(items_rel_sym)
		assert_equal(items_rel_sym, @hierarchical.items)
		@hierarchical.load_item_relations_to_terms(items_rel,false,true)
		assert_equal(items_rel_concat, @hierarchical.items)
		@hierarchical.load_item_relations_to_terms(items_rel_sym,true,true) # here third must no be relevant
		assert_equal(items_rel_sym, @hierarchical.items)

    end

	def test_defining_items_from_instance_variable
		@hierarchical.set_items_from_dict(:is_a)
		assert_equal({:Child2=>[:Parental]}, @hierarchical.items)
		@hierarchical.items = {} # Reseting items variable

		@hierarchical.add_profile(:A, [:Child2, :Parental], substitute: false) # Add profiles
		@hierarchical.add_profile(:B, [:Child2, :Parental, :FakeID], substitute: false)
		@hierarchical.add_profile(:C, [:Child2, :Parental], substitute: false)
		@hierarchical.add_profile(:D, [:Parental], substitute: false)
		# Profiles dictionary
		@hierarchical.get_items_from_profiles
		assert_equal({Child2: [:A, :B, :C], Parental: [:A, :B, :C, :D]}, @hierarchical.items)
	end

	def test_defining_instance_variables_from_items
		@hierarchical.set_items_from_dict(:is_a)
		@hierarchical.get_profiles_from_items
		assert_equal({:Parental=>[:Child2]},@hierarchical.profiles)
	end

	def test_expand_items
		# Add items
		initial_items = {root: [:branchA], Child1: [:branchAChild1], Child2: [:branchAChild1, :branchAChild2, :branchB]}
		exact_expand = {root: [:branchA, :branchAChild1], Child1: [:branchAChild1], Child2: [:branchAChild1, :branchAChild2, :branchB]}
		onto_expand = {root: [:branchA, :branchAChild1], Child1: [:branchAChild1], Child2: [:branchAChild1, :branchAChild2, :branchB]}
		onto_cleaned_expand = {root: [:branchAChild1], Child1: [:branchAChild1], Child2: [:branchAChild1, :branchAChild2, :branchB]}
		@short_hierarchical.load_item_relations_to_terms(initial_items)
		# Expand to parentals (exact match)
		@short_hierarchical.expand_items_to_parentals()
		assert_equal(exact_expand, @short_hierarchical.items)
		# Expand to parentals (MICAS)
		@short_hierarchical.load_item_relations_to_terms(initial_items, true)
		@short_hierarchical.expand_items_to_parentals(ontology: @enrichment_hierarchical, clean_profiles: false)
		assert_equal(onto_expand, @short_hierarchical.items)
		@short_hierarchical.load_item_relations_to_terms(initial_items, true)
		@short_hierarchical.expand_items_to_parentals(ontology: @enrichment_hierarchical)
		assert_equal(onto_cleaned_expand, @short_hierarchical.items)
		###########################
		## NOW INCLUDING NOT STORED TERMS
		###########################
		initial_items = {Child1: [:branchAChild1], Child2: [:branchAChild2, :branchB]}
		onto_notroot_items = {root: [:branchA], Child1: [:branchAChild1], Child2: [:branchAChild2, :branchB]}
		@short_hierarchical.load_item_relations_to_terms(initial_items, true)
		@short_hierarchical.expand_items_to_parentals(ontology: @enrichment_hierarchical, clean_profiles: false)
		assert_equal(onto_notroot_items, @short_hierarchical.items)		
	end

	#################################
	# AUXILIAR METHODS
	#################################

	def test_auxiliar_methods
		iteration_with_custom_each = [] 
		@hierarchical.each(att=true) do |id, tags|
			iteration_with_custom_each << [id, tags]
		end
		assert_equal([[:Parental, {:id=>:Parental, :name=>"All", :comment=>"none"}], 
			[:Child2, {:id=>:Child2, :name=>"Child2", :synonym=>["\"1,6-alpha-mannosyltransferase activity\" EXACT []"], 
			 :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}]],
			 iteration_with_custom_each)
		assert_equal([:Parental],@hierarchical.get_root)
		assert_equal([[:Parental, "All", 1], [:Child2, "Child2", 2]], @hierarchical.list_term_attributes)

	end

end 
