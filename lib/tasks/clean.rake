def hash_to_yaml(hash, depth=0)
  code = ''
  for k, v in hash.to_a.sort{|a,b| a[0].to_s.gsub("_"," ").strip<=>b[0].to_s.gsub("_"," ").strip}
    code += "  "*depth+k.to_s+":"+(v.is_a?(Hash) ? "\n"+hash_to_yaml(v,depth+1) : " '"+v.gsub("'", "''")+"'\n") if v
  end
  code
end

def yaml_to_hash(filename)
  hash = YAML::load(IO.read(filename).gsub(/^(\s*)no:(.*)$/, '\1__no_is_not__false__:\2'))
  return deep_symbolize_keys(hash)
end
  
def deep_symbolize_keys(hash)
  hash.inject({}) { |result, (key, value)|
    value = deep_symbolize_keys(value) if value.is_a? Hash
    key = :no if key.to_s == "__no_is_not__false__"
    result[(key.to_sym rescue key) || key] = value
    result
  }
end


def yaml_value(value, depth=0)
  if value.is_a?(Array)
    "["+value.collect{|x| yaml_value(x)}.join(", ")+"]"
  elsif value.is_a?(Symbol)
    ":"+value.to_s
  elsif value.is_a?(Hash)
    "\n"+hash_to_yaml(value, depth+1)
  else
    "'"+value.to_s.gsub("'", "''")+"'"
  end
end

def hash_diff(hash, ref, depth=0)
  hash ||= {}
  ref ||= {}
  keys = (ref.keys+hash.keys).uniq.sort{|a,b| a.to_s.gsub("_"," ").strip<=>b.to_s.gsub("_"," ").strip}
  code, count, total = "", 0, 0
  for key in keys
    h, r = hash[key], ref[key]
    total += 1 if r.is_a? String
    if r.is_a?(Hash) and (h.is_a?(Hash) or h.nil?)
      scode, scount, stotal = hash_diff(h, r, depth+1)
      code  += "  "*depth+key.to_s+":\n"+scode
      count += scount
      total += stotal
    elsif r and h.nil?
      code  += "  "*depth+"#>"+key.to_s+": "+yaml_value(r)+"\n"
      count += 1
    elsif r and h and r.class == h.class
      code  += "  "*depth+key.to_s+": "+yaml_value(h)+"\n"
    elsif r and h and r.class != h.class
      puts [h,r].inspect
      code  += "  "*depth+key.to_s+": "+(yaml_value(h)+"\n").gsub(/\n/, " #! #{r.class.name} excepted (#{h.class.name+':'+h.inspect})\n")
    elsif h and r.nil?
      code  += "  "*depth+key.to_s+": "+(yaml_value(h)+"\n").to_s.gsub(/\n/, " #!\n")
    elsif r.nil?
      code  += "  "*depth+key.to_s+":\n"
    end
  end  
  return code, count, total
end


namespace :clean do



  desc "Update models list file in lib/models.rb"
  task :models => :environment do
    
    Dir.glob(RAILS_ROOT + '/app/models/*.rb').each { |file| require file }
    models = Object.subclasses_of(ActiveRecord::Base).select{|x| not x.name.match('::')}.sort{|a,b| a.name <=> b.name}
    models_code = "EKYLIBRE_MODELS = ["+models.collect{|m| ":"+m.name.underscore}.join(", ")+"]\n"
    
    symodels = models.collect{|x| x.name.underscore.to_sym}

    errors = 0
    require "#{RAILS_ROOT}/lib/models.rb"
    # refs = defined?(EKYLIBRE_REFERENCES) ? EKYLIBRE_REFERENCES : {}
    refs = EKYLIBRE_REFERENCES
    refs_code = ""
    for model in models
      m = model.name.underscore.to_sym
      cols = []
      model.columns.sort{|a,b| a.name<=>b.name}.each do |column|
        c = column.name.to_sym
        if c.to_s.match(/_id$/)
          val = (refs[m].is_a?(Hash) ? refs[m][c] : nil)
          val = ((val.nil? or val.blank?) ? "''" : val.inspect)
          if c == :parent_id
            val = ":#{m}"
          elsif [:creator_id, :updater_id].include? c
            val = ":user"
          elsif symodels.include? c.to_s[0..-4].to_sym
            val = ":#{c.to_s[0..-4]}"
          end
          errors += 1 if val == "''"
          cols << "    :#{c} => #{val}"
        end
      end
      refs_code += "\n  :#{m} => {\n"+cols.join(",\n")+"\n  },"
    end
    puts " - Models: #{errors} errors"
    refs_code = "EKYLIBRE_REFERENCES = {"+refs_code[0..-2]+"\n}\n"

    File.open("#{RAILS_ROOT}/lib/models.rb", "wb") do |f|
      f.write("# Autogenerated from Ekylibre (`rake clean:models` or `rake clean`)\n")
      f.write("# List of all models\n")
      f.write(models_code)
      f.write("\n# List of all references\n")
      f.write(refs_code)
    end

  end


  desc "Look at bad and suspect views"
  task :views => :environment do

    views = []
    for controller_file in Dir.glob("#{RAILS_ROOT}/app/controllers/*.rb").sort
      source = ""
      File.open(controller_file, "rb") do |f|
        source = f.read
      end
      controller = controller_file.split(/[\\\/]+/)[-1].gsub('_controller.rb', '')
      for file in Dir.glob("#{RAILS_ROOT}/app/views/#{controller}/*.*").sort
        action = file.split(/[\\\/]+/)[-1].split('.')[0]
        valid = false
        valid = true if not valid and source.match(/^\s*def\s+#{action}\s*$/)
        valid = true if not valid and action.match(/^_\w+_form$/) and (source.match(/^\s*def\s+#{action[1..-6]}_(upd|cre)ate\s*$/) or source.match(/^\s*manage\s*\:#{action[1..-6].pluralize}(\W|$)/))
        if action.match(/^_/) and not valid
          if source.match(/^[^\#]*(render|replace_html)[^\n]*partial[^\n]*#{action[1..-1]}/)
            valid = true 
          else
            for view in Dir.glob("#{RAILS_ROOT}/app/views/#{controller}/*.*")
              File.open(view, "rb") do |f|
                view_source = f.read
                if view_source.match(/(render|replace_html)[^\n]*partial[^\n]*#{action[1..-1]}/)
                  valid = true
                  break
                end
              end
            end
          end
        end
        views << file.gsub(RAILS_ROOT, '.') unless valid
      end
    end
    puts " - Views: #{views.size} potentially bad views"
    for view in views
      puts "   #{view}"
    end
  end



  desc "Update and sort rights list"
  task :rights => :environment do
    new_right = '__not_used__'

    # Chargement des actions des controllers
    ref = {}
    Dir.glob("#{RAILS_ROOT}/app/controllers/*_controller.rb") do |x|
      controller_name = x.split("/")[-1].split("_controller")[0]
      actions = []
      file = File.open(x, "r")
      file.each_line do |line|
        line = line.gsub(/(^\s*|\s*$)/,'')
        if line.match(/^\s*def\s+\w+\s*$/)
          actions << line.split(/def\s/)[1].gsub(/\s/,'') 
        elsif line.match(/^\s*dy(li|ta)[\s\(]+\:\w+/)
          dyxx = line.split(/[\s\(\)\,\:]+/)
          actions << dyxx[1]+'_'+dyxx[0]
        elsif line.match(/^\s*manage[\s\(]+\:\w+/)
          prefix = line.split(/[\s\(\)\,\:]+/)[1].singularize
          actions << prefix+'_create'
          actions << prefix+'_update'
          actions << prefix+'_delete'
        end
      end
      ref[controller_name] = actions.sort
    end

    # Lecture du fichier existant
    rights = YAML.load_file(User.rights_file)

    # Expand actions
    for right, attributes in rights
      attributes['actions'].each_index do |index|
        unless attributes['actions'][index].match(/\:\:/)
          attributes['actions'][index] = attributes['controller'].to_s+"::"+attributes['actions'][index] 
        end
      end if attributes['actions'].is_a? Array
    end
    rights_list  = rights.keys.sort
    actions_list = rights.values.collect{|x| x["actions"]||[]}.flatten.uniq.sort

    # Ajout des nouvelles actions
    created = 0
    for controller, actions in ref
      for action in actions
        uniq_action = controller+"::"+action
        unless actions_list.include?(uniq_action)
          rights[new_right] ||= {}
          rights[new_right]["actions"] ||= []
          rights[new_right]["actions"] << uniq_action
          created += 1
        end
      end
    end

    # Commentaire des actions supprimées
    deleted = 0
    for right, attributes in rights
      attributes['actions'].each_index do |index|
        uniq_action = attributes["actions"][index]
        controller, action = uniq_action.split(/\W+/)[0..1]
        unless ref[controller].include?(action)
          attributes["actions"][index] += " # UNEXISTENT ACTION !!!"
          deleted += 1
        end
      end if attributes['actions'].is_a?(Array)
    end

    # Enregistrement du nouveau fichier
    code = ""
    for right in rights.keys.sort
      code += "# #{::I18n.translate('rights.'+right.to_s)}\n"
      code += "#{right}:\n"
      # code += "#{right}: # #{::I18n.translate('rights.'+right.to_s)}\n"
      controller, actions = rights[right]['controller'], []
      code += "  controller: #{controller}\n" unless controller.blank?
      if rights[right]["actions"].is_a?(Array)
        actions = rights[right]['actions'].sort
        actions = actions.collect{|x| x.match(/^#{controller}\:\:/) ? x.split('::')[1] : x}.sort unless controller.blank?
        line = "  actions: [#{actions.join(', ')}]"
        if line.length > 80 or line.match(/\#/)
        # if line.match(/\#/)
          code += "  actions:\n"
          for action in actions
            code += "  - #{action}\n"
          end
        else
          code += line+"\n"
        end
      end
    end
    File.open(User.rights_file, "wb") do |file|
      file.write code
    end

    puts " - Rights: #{deleted} deletable actions, #{created} created actions"
  end



  desc "Update and sort translation files"
  task :locales => :environment do
    log = File.open("#{RAILS_ROOT}/config/locales/translations.log", "wb")

    # Load of actions
    all_actions = {}
    for right, attributes in YAML.load_file(User.rights_file)
      for full_action in attributes['actions']
        controller, action = (full_action.match(/\:\:/) ? full_action.split(/\W+/)[0..1] : [attributes['controller'].to_s, full_action])
        all_actions[controller] ||= []
        all_actions[controller] << action unless action.match /dy(li|ta)|delete/
      end if attributes['actions'].is_a? Array
    end
    useful_actions = all_actions.dup
    useful_actions.delete("authentication")
    useful_actions.delete("help")

    locale = ::I18n.locale = ::I18n.default_locale
    locale_dir = "#{RAILS_ROOT}/config/locales/#{locale}"
    File.makedirs(locale_dir) unless File.exist?(locale_dir)
    File.makedirs(locale_dir+"/help") unless File.exist?(locale_dir+"/help")
    log.write("Locale #{::I18n.locale_label}:\n")

    # Activerecord
    models = Dir["#{RAILS_ROOT}/app/models/*.rb"].collect{|m| m.split(/[\\\/\.]+/)[-2]}.sort
    default_attributes = ::I18n.translate("activerecord.default_attributes")
    models_names, plurals_names, models_attributes = '', '', ''
    attrs_count, static_attrs_count = 0, 0
    for model in models
      class_name = model.sub(/\.rb$/,'').camelize
      klass = class_name.split('::').inject(Object){ |klass,part| klass.const_get(part) }
      if klass < ActiveRecord::Base && !klass.abstract_class?
        models_names  += "      #{model}: "+::I18n.pretranslate("activerecord.models.#{model}")+"\n"
        plurals_names += "      #{model}: "+::I18n.pretranslate("activerecord.models_plurals.#{model}")+"\n"
        models_attributes += "\n      # #{::I18n.t("activerecord.models.#{model}")}\n"
        models_attributes += "      #{model}:\n"
        attributes = {}
        for k, v in ::I18n.translate("activerecord.attributes.#{model}")||{}
          attributes[k] = "'"+v.gsub("'","''")+"'" if v
        end
        static_attrs_count += klass.columns.size
        for column in klass.columns
          attribute = column.name.to_sym
          trans = default_attributes[attribute]
          pretrans = ::I18n.pretranslate("activerecord.attributes.#{model}.#{attribute}")
          if trans.nil? and pretrans.match(/^\(\(\(/)
            trans = attribute.to_s[0..-4].classify.constantize.human_name rescue nil
          end
          trans = trans.nil? ? pretrans : "'"+trans.gsub("'","''")+"'"
          attributes[attribute] = trans
        end
        # Add reflections in attributes
        #raise Exception.new klass.reflections.inspect
        for reflection, details in klass.reflections
          attribute = reflection.to_sym
          trans   = ::I18n.hardtranslate("activerecord.attributes.#{model}.#{attribute}")
          trans ||= ::I18n.hardtranslate("activerecord.attributes.#{model}.#{attribute}_id")
          trans ||= ::I18n.hardtranslate("activerecord.models_plurals.#{attribute.to_s.singularize}")
          trans ||= ::I18n.hardtranslate("activerecord.models_plurals.#{model}_#{attribute.to_s.singularize}")
          attributes[attribute] = (trans.nil? ? "(((#{attribute.to_s.upper})))" : "'"+trans.gsub("'","''")+"'")
        end
        for x in [:creator, :updater]
          attributes[x] ||= "'"+default_attributes[x].gsub("'","''")+"'"
        end

        # Sort attributes and build yaml
        methods = klass.instance_methods+klass.columns_hash.keys+["creator", "updater"]
        for attribute, trans in attributes.to_a.sort{|a,b| a[0].to_s<=>b[0].to_s}
          models_attributes += "        #{attribute}: "+trans
          models_attributes += " #?" unless methods.include?(attribute.to_s)
          models_attributes += "\n"
        end
        attrs_count += attributes.size
      else
        # puts "Skipping #{class_name}"
      end
    end
    activerecord = ::I18n.translate('activerecord').delete_if{|k,v| k.to_s.match(/^models|attributes$/)}
    translation  = locale.to_s+":\n"
    translation += "  activerecord:\n"
    translation += hash_to_yaml(activerecord, 2)
    translation += "\n    models:\n"
    translation += models_names
    translation += "\n    models_plurals:\n"
    translation += plurals_names
    translation += "\n    default_attributes:\n"
    translation += hash_to_yaml(default_attributes, 3)
    translation += "\n    attributes:\n"
    translation += models_attributes
    File.open("#{RAILS_ROOT}/config/locales/#{locale}/activerecord.yml", "wb") do |file|
      file.write translation
    end
    log.write "  - Models (#{models.size}, #{static_attrs_count} static attributes, #{attrs_count-static_attrs_count} virtual attributes, #{(attrs_count.to_f/models.size).round(1)} attributes/models)\n"

    # Packs
    controllers = Dir["#{RAILS_ROOT}/app/controllers/*.rb"].collect{|m| m.split(/[\\\/\.]+/)[-2]}.sort
    log.write "  - Packs (#{controllers.size})\n"
    for controller in controllers
      controller_name = controller.split("_")[0..-2].join("_")
      translation  = locale.to_s+":\n"
      for part in [:controllers, :helpers]
        translation += "\n  #{part}:\n"
        translation += "    #{controller_name}:\n"
        translation += hash_to_yaml(::I18n.translate("#{part}.#{controller_name}"), 3)
      end
      # Views with checks
      views = ::I18n.translate("views.#{controller_name}")
      translation += "\n  views:\n"
      translation += "    #{controller_name}:\n"
      builders = [".html.haml", ".rjs"]
      unused_translations, missing_translations, unfound_views, unfound_actions = 0, 0, 0, 0
      for view, items in views.sort{|a,b| a[0].to_s.gsub("_"," ").strip<=>b[0].to_s.gsub("_"," ").strip}
        # Test if there is an action for classic views
        if not view.to_s.match(/^_/) and not (all_actions[controller_name]||[]).include?(view.to_s)
          translation += "      # No defined action for this view !!!\n"
          unfound_actions += 1
        end
        # Search for a file
        file = "#{RAILS_ROOT}/app/views/#{controller_name}/#{view}"
        file_found = false
        for builder in builders
          if File.exist?(file+builder)
            file += builder
            file_found = true
            break
          end
        end
        # Test presence of view's file
        if file_found
          translation += "      #{view}:\n"
          source = ""
          File.open(file, "rb") do |f|
            source = f.read
          end
          for item, data in items.sort{|a,b| a[0].to_s<=>b[0].to_s}
            code = yaml_value(data, 4)
            regexp = /((\W|^)tc|(\.|\-\s*)link|\.title)\s*\(?\s*(\"#{item}\"|\'#{item}\'|\:#{item}(\W|$))/
            unless source.match(regexp) or [:title].include?(item)
              code.gsub!(/$/, " #!\n")
              unused_translations += 1
            end
            translation += "        #{item}: "+code+"\n"
          end
          # Add potentially missing translations
          regexp = /((\W|^)tc|(\.|\-\s*)link|\.title)\s*\(?\s*(\"\w+\"|\'\w+\'|\:\w+(\W|$))/
          source.gsub(regexp) do |m|
            w = m.match(regexp).to_a[-2]
            if w.is_a? String
              key = w[1..-2].to_sym
              unless items.keys.include? key
                translation += "        #>#{key}: # Potentially missing translation\n"
                missing_translations += 1
              end
            end
          end
        else
          # Test if due to render_form use
          operation = view.to_s.split("_")[-1]
          if File.exist?("#{RAILS_ROOT}/app/views/shared/form_#{operation}.html.haml") and File.exist?(file.gsub(view.to_s, "_#{view.to_s.gsub(operation, 'form.html.haml')}"))
            if items.keys.size > 1
              translation += "      # Possible error because only :title can be used\n"
            end
          else
            translation += "      # Unfound view #{file.gsub(RAILS_ROOT, '.')}\n"
            unfound_views += 1
          end
          translation += "      #{view}:\n"
          translation += yaml_value(items, 3)
        end
      end if views.is_a? Hash
      log.write "    - #{(controller_name+':').ljust(16,' ')} #{unused_translations.to_s.rjust(3)} unused translation(s), #{missing_translations.to_s.rjust(3)} missing translation(s), #{unfound_views.to_s.rjust(3)} unfound view(s), #{unfound_actions.to_s.rjust(3)} unfound action(s)\n"
      File.open("#{RAILS_ROOT}/config/locales/#{locale}/pack.#{controller_name}.yml", "wb") do |file|
        file.write translation.gsub(/\n\n/, "\n")
      end
      # raise Exception.new("Stop")
    end

    
    # Parameters
    translation  = locale.to_s+":\n"
    translation += "  parameters:\n"
    translation += hash_to_yaml(::I18n.translate("parameters"), 2)
    File.open("#{RAILS_ROOT}/config/locales/#{locale}/parameters.yml", "wb") do |file|
      file.write(translation)
    end
    log.write "  - Parameters\n"
    
    # Notifications
    notifications = ::I18n.t("notifications")
    deleted_notifs = ::I18n.t("notifications").keys
    for controller in Dir["#{RAILS_ROOT}/app/controllers/*.rb"]
      file = File.open(controller, "r")
      file.each_line do |line|
        if line.match(/([\s\W]+|^)notify\(\s*\:\w+/)
          key = line.split(/notify\(\s*\:/)[1].split(/\W/)[0]
          deleted_notifs.delete(key.to_sym)
          notifications[key.to_sym] = "" if notifications[key.to_sym].nil? or (notifications[key.to_sym].is_a? String and notifications[key.to_sym].match(/\(\(\(/))
        end
      end
    end

    translation = locale.to_s+":\n"
    translation += "  notifications:\n"
    for key, trans in notifications.sort{|a,b| a[0].to_s<=>b[0].to_s}
      line = "    #{key}: "+(trans.blank? ? '((('+key.to_s.upper+')))' : yaml_value(trans, 2))
      line.gsub!(/$/, "# NOT USED !!!") if deleted_notifs.include?(key)
      translation += line+"\n"
      end
    File.open("#{RAILS_ROOT}/config/locales/#{locale}/notifications.yml", "wb") do |file|
      file.write translation
    end
    log.write "  - Notifications (#{notifications.size}, #{deleted_notifs.size} bad notifications)\n"

    # Rights
    rights = YAML.load_file(User.rights_file)
    translation  = locale.to_s+":\n"
    translation += "  rights:\n"
    for right in rights.keys.sort
      translation += "    #{right}: "+::I18n.pretranslate("rights.#{right}")+"\n"
    end
    File.open("#{RAILS_ROOT}/config/locales/#{locale}/rights.yml", "wb") do |file|
      file.write translation
    end
    log.write "  - Rights (#{rights.keys.size})\n"

    log.write "  - help: # Missing files\n"
    for controller, actions in useful_actions
      for action in actions
        if File.exists?("#{RAILS_ROOT}/app/views/#{controller}/#{action}.html.haml") or (File.exists?("#{RAILS_ROOT}/app/views/#{controller}/_#{action.gsub(/_[^_]*$/,'')}_form.html.haml") and action.split("_")[-1].match(/create|update/))
          help = "#{RAILS_ROOT}/config/locales/#{locale}/help/#{controller}-#{action}.txt"
          log.write "    - #{help.gsub(RAILS_ROOT,'.')}\n" unless File.exists?(help)
        end
      end
    end
    
    puts " - Locale: #{::I18n.locale_label} (Reference)"




    for locale in ::I18n.available_locales.delete_if{|l| l==::I18n.default_locale or l.to_s.size!=3}.sort{|a,b| a.to_s<=>b.to_s}
      ::I18n.locale = locale
      locale_dir = "#{RAILS_ROOT}/config/locales/#{locale}"
      File.makedirs(locale_dir) unless File.makedirs(locale_dir)
      File.makedirs(locale_dir+"/help") unless File.makedirs(locale_dir+"/help")
      log.write "Locale #{::I18n.locale_label}:\n"
      total, count = 0, 0
      for reference_path in Dir.glob("#{RAILS_ROOT}/config/locales/#{::I18n.default_locale}/*.yml").sort
        file_name = reference_path.split(/[\/\\]+/)[-1]
        target_path = "#{RAILS_ROOT}/config/locales/#{locale}/#{file_name}"
        unless File.exist?(target_path)
          File.open(target_path, "wb") do |file|
            file.write("#{locale}:\n")
          end
        end
        target = yaml_to_hash(target_path)
        reference = yaml_to_hash(reference_path)
        translation, scount, stotal = hash_diff(target[locale], reference[::I18n.default_locale], 1)
        count += scount
        total += stotal
        log.write "  - #{file_name}: #{(100*(stotal-scount)/stotal).round}% (#{stotal-scount}/#{stotal})\n"
        File.open(target_path, "wb") do |file|
          file.write("#{locale}:\n")
          file.write(translation)
        end
      end
      log.write "  - total: #{(100*(total-count)/total).round}% (#{total-count}/#{total}) done.\n"
      # Missing help files
      log.write "  - help: # Missing files\n"
      for controller, actions in useful_actions
        for action in actions
          if File.exists?("#{RAILS_ROOT}/app/views/#{controller}/#{action}.html.haml") or (File.exists?("#{RAILS_ROOT}/app/views/#{controller}/_#{action.gsub(/_[^_]*$/,'')}_form.html.haml") and action.split("_")[-1].match(/create|update/))
            help = "#{RAILS_ROOT}/config/locales/#{locale}/help/#{controller}-#{action}.txt"
            log.write "    - #{help.gsub(RAILS_ROOT,'.')}\n" unless File.exists?(help)
          end
        end
      end
      puts " - Locale: #{::I18n.locale_label} #{(100*(total-count)/total).round}% translated"
    end

    log.close
  end
  


  
end


desc "Clean all files as possible"
task :clean=>[:environment, "clean:rights", "clean:models", "clean:views", "clean:locales"]

