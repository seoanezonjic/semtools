class FileParser
	#############################################
    # FIELDS
    #############################################
    # Handled class variables
    # => @@basic_tags :: hash with main OBO structure tags
    # => @@symbolizable_ids :: tags which can be symbolized
    # => @@tags_with_trailing_modifiers :: tags which can include extra info after specific text modifiers

	@@basic_tags = {ancestors: [:is_a], obsolete: :is_obsolete, alternative: [:replaced_by,:consider,:alt_id]}
    @@symbolizable_ids = [:id, :alt_id, :replaced_by, :consider]
    @@tags_with_trailing_modifiers = [:is_a, :union_of, :disjoint_from, :relationship, :subsetdef, :synonymtypedef, :property_value]
    @@multivalue_tags = [:alt_id, :is_a, :subset, :synonym, :xref, :intersection_of, :union_of, :disjoint_from, :relationship, :replaced_by, :consider, :subsetdef, :synonymtypedef, :property_value, :remark]
    @@symbolizable_ids.concat(@@tags_with_trailing_modifiers)

    # Symboliza all values into hashs using symbolizable tags as keys
    # ===== Parameters
    # +item_hash+:: hash to be checked
    def self.symbolize_ids(item_hash)
        @@symbolizable_ids.each do |tag|
            query = item_hash[tag] 
            if !query.nil?
                if query.kind_of?(Array)
                    query.map!{|item| item.to_sym}
                else
                    item_hash[tag] = query.to_sym if !query.nil?
                end
            end
        end
    end

end
