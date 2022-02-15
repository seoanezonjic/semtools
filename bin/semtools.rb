#! /usr/bin/env ruby
ROOT_PATH = File.dirname(__FILE__)
$LOAD_PATH.unshift(File.expand_path(File.join(ROOT_PATH, '..', 'lib')))
EXTERNAL_DATA = File.expand_path(File.join(ROOT_PATH, '..', 'external_data'))

require 'optparse'
require 'down'
require 'semtools'

######################################################################################
## METHODS
######################################################################################
def load_tabular_file(file)
  records = []
  File.open(file).each do |line|
    line.chomp!
    fields = line.split("\t")
    records << fields
  end
  return records
end

def store_profiles(file, ontology, sep = ",")
  file.each do |id, terms|
    terms = terms.split(sep).map!{|term| term.to_sym}  
    ontology.add_profile(id, terms)
  end  
end

def load_value(hash_to_load, key, value, unique = true)
   	query = hash_to_load[key]
    if query.nil?
       value = [value] if value.class != Array
       hash_to_load[key] = value
    else
        if value.class == Array
            query.concat(value)
        else
            query << value
        end
        query.uniq! unless unique == nil
    end
end

def translate(ontology, type, options, profiles = nil)
  not_translated = {}
  if type == 'names'
    ontology.profiles.each do |id, terms|
      translation, untranslated = ontology.translate_ids(terms)
      ontology.profiles[id] = translation  
      not_translated[id] = untranslated unless untranslated.empty?
    end  
  elsif type == 'codes'
    profiles.each do |id,terms|
      translation, untranslated = ontology.translate_names(terms)
      profiles[id] = translation
      profiles[id] = profiles[id].join("#{options[:separator]}") 
      not_translated[id] = untranslated unless untranslated.empty?
    end    
  end
  if !not_translated.empty?
    File.open(options[:untranslated_path], 'w') do |file|
      not_translated.each do |id, terms|
          file.puts([id, terms.join(";")].join("\t"))
      end
    end
  end    
end  

def clean_profile(profile, ontology, options)
	cleaned_profile = ontology.clean_profile_hard(profile)	
	unless options[:term_filter].nil?
		cleaned_profile.select! {|term| ontology.get_ancestors(term).include?(options[:term_filter])}
	end	
	return cleaned_profile
end

def clean_profiles(profiles, ontology, options)
	removed_profiles = []
	profiles.each do |id, terms|
		cleaned_profile = clean_profile(terms, ontology, options)
		profiles[id] = cleaned_profile
		removed_profiles << id if cleaned_profile.empty?
	end
	removed_profiles.each{|rp| profiles.delete(rp)}
	return removed_profiles
end

def expand_profiles(profiles, ontology, unwanted_terms = [])
	profiles.each do |disease_id, terms|
		terms.each do |term|
	    	profiles[disease_id] << ontology.get_ancestors(term).difference(unwanted_terms)
	  end
	end
end	

def write_similarity_profile_list(input, onto_obj, similarity_type)
  similarity_file = File.basename(input, ".*")+'_semantic_similarity_list'  
  File.open(similarity_file, 'w') do |file|
    onto_obj.profiles.each do |profile_query_key, profile_query_value|
      onto_obj.profiles.each do |profile_search_key, profile_search_value|
        file.puts([profile_query_key, profile_search_key, onto_obj.compare(profile_query_value, profile_search_value, sim_type: similarity_type)].join("\t"))
      end
    end 
  end
end

def download(source, key, output)
  source_list = load_tabular_file(source).to_h
  external_data = File.dirname(source)
  if key == 'list'
    Dir.glob(File.join(external_data,'*.obo')){|f| puts f}
  else
    url = source_list[key]
    if !output.nil?
      output_path = output
    else
      file_name = key + '.obo'
      if File.writable?(external_data)
        output_path = File.join(external_data, file_name)
      else
        output_path = file_name
      end
    end
    Down::NetHttp.download(url, destination: output_path, max_redirects: 5) if !url.nil?
  end
end

def get_ontology_file(path, source)
  if !File.exists?(path)
    ont_index = load_tabular_file(source).to_h
    if !ont_index[path].nil?
      path = File.join(File.dirname(source), path + '.obo')
    else
      abort("Input ontology file not exists")
    end
  end
  return path
end

####################################################################################
## OPTPARSE
####################################################################################
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options]"

  options[:download] = nil
  opts.on("-d", "--download STRING", "Download obo file from official resource. MONDO, GO and NPO are possible values.") do |item|
    options[:download] = item
  end

  options[:input_file] = nil
  opts.on("-i", "--input_file PATH", "Filepath of profile data") do |item|
    options[:input_file] = item
  end

  options[:output_file] = nil
  opts.on("-o", "--output_file PATH", "Output filepath") do |item|
    options[:output_file] = item
  end

  options[:IC] = false
  opts.on("-I", "--IC", "Get IC") do
    options[:IC] = true
  end

  options[:ontology_file] = nil
  opts.on("-O PATH", "--ontology_file PATH", "Path to ontology file") do |item|
  	options[:ontology_file] = item
  end

  options[:term_filter] = nil
  opts.on("-T STRING", "--term_filter STRING", "If specified, only terms that are descendants of the specified term will be kept on a profile when cleaned") do |item|
  	options[:term_filter] = item.to_sym
  end

  options[:translate] = nil
  opts.on("-t STRING", "--translate STRING", "Translate to 'names' or to 'codes'") do |item|
  	options[:translate] = item
  end
  
  opts.on("-s method", "--similarity method", "Calculate similarity between profile IDs computed by 'resnik', 'lin' or 'jiang_conrath' methods. ") do |sim_method|
  	options[:similarity] = sim_method.to_sym
  end

  options[:clean_profiles] = false
	opts.on("-c", "--clean_profiles", "Removes ancestors, descendants and obsolete terms from profiles") do
  	options[:clean_profiles] = true
  end

  options[:removed_path] = 'rejected_profs'
  opts.on("-r PATH", "--removed_path PATH", "Desired path to write removed profiles file") do |item|
  	options[:removed_path] = item
  end

  options[:untranslated_path] = nil
  opts.on("-u PATH", "--untranslated_path PATH", "Desired path to write untranslated terms file") do |item|
    options[:untranslated_path] = item
  end

  options[:keyword] = nil
  opts.on("-k STRING", "--keyword STRING", "regex used to get xref terms in the ontology file") do |item|
    options[:keyword] = item
  end

  options[:expand_profiles] = false
  opts.on("-e", "--expand_profiles", "Expand profiles adding ancestors") do
    options[:expand_profiles] = true
  end

  options[:unwanted_terms] = []
  opts.on("-U", "--unwanted_terms STRING", "Comma separated terms not wanted to be included in profile expansion") do |item|
    options[:unwanted_terms] = item
  end

  options[:separator] = ";"
  opts.on("-S STRING", "--separator STRING", "Separator used for the terms profile") do |sep|
    options[:separator] = sep
  end     

  options[:childs] = []
  opts.on("-C STRING", "--separator STRING", "Term code list (comma separated) to generate child list") do |item|
    options[:childs] = item.split(',').map{|t| t.to_sym}
  end   

end.parse!    

####################################################################################
## MAIN
####################################################################################
ont_index_file = File.join(EXTERNAL_DATA, 'ontologies.txt')
if !options[:download].nil?
  download(ont_index_file, options[:download], options[:output_file])
  Process.exit
end

if !options[:ontology_file].nil?
  options[:ontology_file] = get_ontology_file(options[:ontology_file], ont_index_file)
end
ontology = Ontology.new(file: options[:ontology_file], load_file: true)
ontology.calc_dictionary(:xref, select_regex: /(#{options[:keyword]})/, store_tag: :IDs, multiterm: true, substitute_alternatives: false)

if !options[:input_file].nil?
  data = load_tabular_file(options[:input_file])
  store_profiles(data, ontology, options[:separator]) unless options[:translate] == 'codes'
end

if options[:translate] == 'codes'
  profiles = {}
  data.each do |id, terms|
    load_value(profiles, id, terms)
    profiles[id] = terms.split(options[:separator])
  end
  translate(ontology, 'codes', options, profiles)
  store_profiles(profiles, ontology, options[:separator])
end
   
if options[:clean_profiles]
	removed_profiles = clean_profiles(ontology.profiles, ontology, options)	
	if !removed_profiles.nil? && !removed_profiles.empty?
      File.open(options[:removed_path], 'w') do |f|
          removed_profiles.each do |profile|
              f.puts profile
          end
      end
	end
end

if options[:expand_profiles]
  expanded_profiles = expand_profiles(ontology.profiles, ontology, options[:unwanted_terms])
end 

if !options[:similarity].nil?
  write_similarity_profile_list(input = options[:input_file], onto_obj=ontology, similarity_type = options[:similarity])
end 


if options[:IC]
  ontology.add_observed_terms_from_profiles
  by_ontology, by_freq = ontology.get_profiles_resnik_dual_ICs
  ic_file = File.basename(options[:input_file], ".*")+'_IC_onto_freq'
  File.open(ic_file , 'w') do |file|
    ontology.profiles.keys.each do |id|
        file.puts([id, by_ontology[id], by_freq[id]].join("\t"))
    end       
  end
end    

if options[:translate] == 'names'
  translate(ontology, 'names', options)  
end

if !options[:childs].empty?
  all_childs = []
  options[:childs].each do |term|
   childs = ontology.get_descendants(term)
   all_childs = all_childs | childs
  end
  all_childs.each{|c| puts c}
end

if !options[:output_file].nil?
  File.open(options[:output_file], 'w') do |file|
    ontology.profiles.each do |id, terms|
      file.puts([id, terms.join("|")].join("\t"))
    end
  end         
end