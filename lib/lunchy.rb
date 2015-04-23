require 'fileutils'

class String
  def red
    "\033[31m#{self}\033[0m"
  end
end

class Lunchy
  VERSION = '0.8.0'

  LAUNCHD_USER_LOCATIONS =  %w(/Library/LaunchAgents
                              ~/Library/LaunchAgents
                              );
  LAUNCHD_SYSTEM_LOCATIONS = %w(/Library/LaunchDaemons
                                /System/Library/LaunchDaemons
                                /System/Library/LaunchAgents
                               )
  def load(params)
    raise ArgumentError, "load [-wF] [name]" if params.empty?

    with_match params[0] do |name, path|
      execute("launchctl load #{force}#{write}#{path.inspect}")
      puts "loaded #{name}"
    end
  end

  def unload(params)
    if all
      return unload_all(params)
    end
    raise ArgumentError, "unload [-w] [name]" if params.empty?

    with_match params[0] do |name, path|
      execute("launchctl unload #{write}#{path.inspect}")
      puts "unloaded #{name}"
    end
  end

  def unload_all(params)
    daemons = status(params).split("\n").map! {|l| l.split(" ")[-1]}
    if daemons.size > 0
      daemons.each{ |daemon|  with_match daemon do |name, path|
        execute("launchctl unload #{write}#{path.inspect}")
        puts "unloaded #{name}"
      end
      }
    else
      puts "no agents found to be unloaded"
    end
  end

  def reload(params)
    unload(params.dup)
    load(params.dup)
  end

  def status(params)
    pattern = params[0]
    cmd = "launchctl list"

    unless verbose?
      agents = plists.keys.map { |k| "-e \"#{k}\"" }.join(" ")
      cmd << " | grep -i #{agents}"
    end

    cmd.gsub!('.','\.')
    cmd << " | grep -i \"#{pattern}\"" if pattern
    execute(cmd)
  end

  def ls(params)
    agents = plists.keys
    agents = agents.grep(/#{params[0]}/i) if !params.empty?
    if long
      puts agents.map { |agent| plists[agent] }.sort.join("\n")
    else
      puts agents.sort.join("\n")
    end
  end
  alias_method :list, :ls

  def install(params)
    raise ArgumentError, "install [-s] [file]" if params.empty?
    filename = params[0]
    %w(~/Library/LaunchAgents /Library/LaunchAgents).each do |dir|
      if File.exist?(File.expand_path(dir))
        if symlink
          FileUtils.ln_s filename, File.join(File.expand_path(dir), File.basename(filename)), force: true
          return puts "#{filename} installed to #{dir}"
        else
          FileUtils.cp filename, File.join(File.expand_path(dir), File.basename(filename))
          return puts "#{filename} installed to #{dir}"
        end
      end
    end
  end

  def uninstall(params)
    raise ArgumentError, "uninstall [name]" if params.empty?

    unload(params.dup)

    with_match params[0] do |name, path|
      if File.exist?(path)
        FileUtils.rm(path)
        puts "uninstalled #{name}"
      end
    end
  end
  alias_method :rm, :uninstall

  def show(params)
    raise ArgumentError, "show [name]" if params.empty?

    with_match params[0] do |_, path|
      puts IO.read(path)
    end
  end

  def edit(params)
    raise ArgumentError, "edit [name]" if params.empty?

    with_match params[0] do |_, path|
      editor = ENV['EDITOR']
      if editor.nil?
        raise 'EDITOR environment variable is not set'
      else
        execute("#{editor} #{path.inspect} > `tty`")
      end
    end
  end

  def search(params)
    IO.popen("
      IFS=$'\n';
      find #{(LAUNCHD_USER_LOCATIONS+LAUNCHD_SYSTEM_LOCATIONS).join(" ")} -type f -exec \\
      grep --exclude-dir={.bzr,.cvs,.git,.hg,.svn} -IinHE \'#{params.join("|")}\' {} \\;") {|f|
            puts f.readlines.map {|str| str.gsub(/#{params.join("|")}/i,&:red)}
         }
  end

  def locations(params)
    puts (LAUNCHD_SYSTEM_LOCATIONS+LAUNCHD_USER_LOCATIONS).join("\n")
  end

  private

  def force
    CONFIG[:force] and '-F '
  end

  def write
    CONFIG[:write] and '-w '
  end

  def long
    CONFIG[:long]
  end

  def symlink
    CONFIG[:symlink]
  end

  def all
    CONFIG[:all]
  end

  def with_match(name)
    files = plists.select {|k,_| k =~ /#{name}/i }
    files = Hash[files] if files.is_a?(Array) # ruby 1.8

    if files.size > 1
      puts "Multiple daemons found matching '#{name}'. You need to be more specific. Matches found are:\n#{files.keys.join("\n")}"
    elsif files.empty?
      puts "No daemon found matching '#{name}'" unless name
    else
      yield(*files.to_a.first)
    end
  end

  def execute(cmd)
    puts "Executing: #{cmd}" if verbose?
    emitted = `#{cmd}`
    puts emitted unless emitted.empty?
    emitted
  end

  def plists
    @plists ||= begin
      plists = {}
      plist_locations.each do |plist_location|
        Dir["#{File.expand_path(plist_location)}/*.plist"].inject(plists) do |memo, filename|
          memo[File.basename(filename, ".plist")] = filename; memo
        end
      end
      plists
    end
  end

  def plist_locations
    result = LAUNCHD_USER_LOCATIONS
    result.push LAUNCHD_SYSTEM_LOCATIONS if Process.euid == 0
    result
  end

  def verbose?
    CONFIG[:verbose]
  end
end
