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

def format_tabular_data(data, separator, id_col, terms_col)
    data.map!{|row| 
      [row[id_col], 
       row[terms_col].split(separator).map!{|term| term.to_sym}]
    }
end

def store_profiles(file, ontology)
  file.each do |id, terms|
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

def write_similarity_profile_list(output, onto_obj, similarity_type, refs)
  profiles_similarity = onto_obj.compare_profiles(sim_type: similarity_type, external_profiles: refs)
  File.open(output, 'w') do |f|
    profiles_similarity.each do |pairsA, pairsB_and_values|
      pairsB_and_values.each do |pairsB, values|
        f.puts "#{pairsA}\t#{pairsB}\t#{values}"
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
    if !url.nil?
      Down::NetHttp.download(url, destination: output_path, max_redirects: 5)
      File.chmod(0644, output_path) # Correct file permissions set by down gem
    end
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

def get_stats(stats)
  report_stats = []
  report_stats << ['Elements', stats[:count]]
  report_stats << ['Elements Non Zero', stats[:countNonZero]]
  report_stats << ['Non Zero Density', stats[:countNonZero].fdiv(stats[:count])]
  report_stats << ['Max', stats[:max]]
  report_stats << ['Min', stats[:min]]
  report_stats << ['Average', stats[:average]]
  report_stats << ['Variance', stats[:variance]]
  report_stats << ['Standard Deviation', stats[:standardDeviation]]
  report_stats << ['Q1', stats[:q1]]
  report_stats << ['Median', stats[:median]]
  report_stats << ['Q3', stats[:q3]]
  return report_stats
end

def sort_terms_by_levels(terms, modifiers, ontology, all_childs)
  term_levels = ontology.get_terms_levels(all_childs)
  if modifiers.include?('a')
    term_levels.sort!{|t1,t2| t2[1] <=> t1[1]}
  else
    term_levels.sort!{|t1,t2| t1[1] <=> t2[1]}
  end
  all_childs = term_levels.map{|t| t.first}
  return all_childs, term_levels
end

  def get_childs(ontology, terms, modifiers)
    #modifiers
    # - a: get ancestors instead of decendants
    # - r: get parent-child relations instead of list descendants/ancestors
    # - hN: when list of relations, it is limited to N hops from given term
    # - n: give terms names instead of term codes
    all_childs = []
    terms.each do |term|
      if modifiers.include?('a') 
        childs = ontology.get_ancestors(term)
      else
        childs = ontology.get_descendants(term)
      end
      all_childs = all_childs | childs
    end
    if modifiers.include?('r')
      relations = []
      all_childs = all_childs | terms # Add parents that generated child list
      target_hops = nil
      if /h([0-9]+)/ =~ modifiers
        target_hops = $1.to_i + 1 # take into account refernce term (parent/child) addition
        all_childs, term_levels = sort_terms_by_levels(terms, modifiers, ontology, all_childs)
      end

      current_level = nil
      hops = 0
      all_childs.each_with_index do |term, i|
        if !target_hops.nil?
          level = term_levels[i][1]
          if level != current_level
            current_level = level
            hops +=1
            break if hops == target_hops + 1 # +1 take into account that we have detected a level change and we saved the last one entirely
          end
        end
        if modifiers.include?('a')
          descendants = ontology.get_direct_ancentors(term)
        else
          descendants = ontology.get_direct_descendants(term)
        end
        if !descendants.nil?
          descendants.each do |desc|
            if modifiers.include?('a')
              relations << [desc, term]
            else
              relations << [term, desc]
            end
          end
        end
      end
      all_childs = []
      relations.each do |rel| 
        rel, _ = ontology.translate_ids(rel) if modifiers.include?('n')
        all_childs << rel
      end
    else
      all_childs.map!{|c| ontology.translate_id(c)} if modifiers.include?('n') 
    end
    return all_childs
  end



####################################################################################
## OPTPARSE
####################################################################################
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options]"

  options[:download] = nil
  opts.on("-d", "--download STRING", "Download obo file from official resource. MONDO, GO and HPO are possible values.") do |item|
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

  options[:reference_profiles] = nil
  opts.on("--reference_profiles PATH", "Path to file tabulated file with first column as id profile and second column with ontology terms separated by separator. ") do |opt|
    options[:reference_profiles] = opt
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

  options[:xref_sense] = :byValue
  opts.on("--xref_sense ", "Ontology-xref or xref-ontology. By default xref-ontology if set, ontology-xref") do
    options[:xref_sense] = :byTerm
  end

  options[:expand_profiles] = nil
  opts.on("-e", "--expand_profiles STRING", "Expand profiles adding ancestors if 'parental', adding new profiles if 'propagate'") do |meth|
    options[:expand_profiles] = meth 
  end

  options[:unwanted_terms] = []
  opts.on("-U", "--unwanted_terms STRING", "Comma separated terms not wanted to be included in profile expansion") do |item|
    options[:unwanted_terms] = item
  end

  options[:separator] = ";"
  opts.on("-S STRING", "--separator STRING", "Separator used for the terms profile") do |sep|
    options[:separator] = sep
  end     

  options[:childs] = [[], '']
  opts.on("-C STRING", "--childs STRING", "Term code list (comma separated) to generate child list") do |item|
    if item.include?('/')
      modifiers, terms = item.split('/')
    else
      modifiers = ''
      terms = item
    end
    terms = terms.split(',').map{|t| t.to_sym}
    options[:childs] = [terms, modifiers]
  end   

  options[:statistics] = false
  opts.on("-n", "--statistics", "To obtain main statistical descriptors of the profiles file") do
    options[:statistics] = true
  end

  options[:list_translate] = nil
  opts.on("-l STRING", "--list_translate STRING", "Translate to 'names' or to 'codes' input list") do |sep|
    options[:list_translate] = sep
  end     

  options[:subject_column] = 0
  opts.on("-f NUM", "--subject_column INTEGER", "The number of the column for the subject id") do |ncol|
    options[:subject_column] = ncol.to_i
  end

  options[:annotations_column] = 1
  opts.on("-a NUM", "--annotations_column INTEGER", "The number of the column for the annotation ids") do |item|
    options[:annotations_column] = item.to_i
  end

  options[:root] = nil
  opts.on("-R STRING", "--root STRING", "Term id to be considered the new root of the ontology") do |item|
    options[:root] = item.to_sym
  end

  options[:list_term_attributes] = false
  opts.on("--list_term_attributes", "The number of the column for the annotation ids") do
    options[:list_term_attributes] = true
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
Ontology.mutate(options[:root], ontology, clone: false) if !options[:root].nil?
if !options[:input_file].nil?
  data = load_tabular_file(options[:input_file])
  if options[:list_translate].nil? || !options[:keyword].nil?
    format_tabular_data(data, options[:separator], options[:subject_column], options[:annotations_column])
    store_profiles(data, ontology) if options[:translate] != 'codes' && options[:keyword].nil?
  end
end

if !options[:list_translate].nil?
  data.each do |term|
    if options[:list_translate] == 'names'
      translation, untranslated = ontology.translate_ids(term)
    elsif options[:list_translate] == 'codes'
      translation, untranslated = ontology.translate_names(term)
    end
    puts "#{term.first}\t#{translation.empty? ? '-' : translation.first}"
  end
  Process.exit
end

if options[:translate] == 'codes'
  profiles = {}
  data.each do |id, terms|
    load_value(profiles, id, terms)
    profiles[id] = terms.split(options[:separator])
  end
  translate(ontology, 'codes', options, profiles)
  store_profiles(profiles, ontology)
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

if !options[:expand_profiles].nil?
  ontology.expand_profiles(options[:expand_profiles], unwanted_terms: options[:unwanted_terms])
end 

if !options[:similarity].nil?
  refs = nil
  if !options[:reference_profiles].nil?
    refs = load_tabular_file(options[:reference_profiles])
    format_tabular_data(refs, options[:separator], 0, 1)
    refs = refs.to_h
    refs = clean_profiles(ontology.profiles, ontology, options) if options[:clean_profiles]
    abort('Reference profiles are empty after cleaning ') if refs.nil? || refs.empty?
  end
  write_similarity_profile_list(options[:output_file], ontology, options[:similarity], refs)
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

if !options[:childs].first.empty?
  terms, modifiers = options[:childs]
  all_childs = get_childs(ontology, terms, modifiers)
  all_childs.each do |ac|
    if modifiers.include?('r')
      puts ac.join("\t")
    else
      puts ac
    end
  end
end

if !options[:output_file].nil? && options[:similarity].nil?
  File.open(options[:output_file], 'w') do |file|
    ontology.profiles.each do |id, terms|
      file.puts([id, terms.join("|")].join("\t"))
    end
  end         
end

if options[:statistics]
  get_stats(ontology.profile_stats).each do |stat|
    puts stat.join("\t")
  end
end

if options[:list_term_attributes]
  term_attributes = ontology.list_term_attributes
  term_attributes.each do |t_attr|
    t_attr[0] = t_attr[0].to_s
    puts t_attr.join("\t")
  end
end

if !options[:keyword].nil?
  xref_translated = []
  ontology.calc_dictionary(:xref, select_regex: /(#{options[:keyword]})/, store_tag: :tag, multiterm: true, substitute_alternatives: false)
  dict = ontology.dicts[:tag][options[:xref_sense]]
  data.each do |id, prof|
    xrefs = []
    prof.each do |t|
      query = dict[t.to_s]
      xrefs.concat(query) if !query.nil?
    end
    xref_translated << [id, xrefs] if !xrefs.empty?
  end
  File.open(options[:output_file], 'w') do |f|
    xref_translated.each do |id, prof|
      prof.each do |t|
        f.puts [id, t].join("\t")
      end
    end
  end
end