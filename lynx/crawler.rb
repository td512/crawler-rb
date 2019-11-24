require 'open3'
require 'optparse'

# This implementation uses lynx to scan. It's inefficient, but works well

lynx_bins = "lynx"
lynx_args = '-dump -nonumbers -listonly'
# The base URL, or where we would like this script to scan
base = 'http://the-eye.eu/public/'

######################
# DO NOT TOUCH ME    #
######################
dir_count = 0        #
file_count = 0       #
directory = []       #
dir_scanned = []     #
file = []            #
silent = false       #
super_silent = false #
wait_time = 5        #
export = "wget"      #
######################
# DO NOT TOUCH ME    #
######################

def valid_url?(url)
  uri = URI.parse(url)
  (uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)) && !uri.host.nil?
rescue URI::InvalidURIError
  false
end

OptionParser.new do |parser|
  parser.on('-s', '--silent') do |s|
    silent = true
  end
  parser.on('-S', '--supersilent') do |s|
    super_silent = true
  end
  parser.on('-o', '--output') do |o|

  end
  parser.on('-l', '--lynx[=LYNX]') do |lynx|
    lynx_bins = lynx
  end
  parser.on('-u', '--url[=URL]') do |url|
    base = url if valid_url?(url)
  end
  parser.on('-l', '--lynx [LYNX]') do |lynx|
    lynx_bins = lynx
  end
  parser.on('-u', '--url [URL]') do |url|
    base = url if valid_url?(url)
  end
  parser.on('-w', '--wait [TIME]') do |time|
    wait_time = time if time.is_a? Integer
  end
  parser.on('-w', '--wait[=TIME]') do |time|
    wait_time = time if time.is_a? Integer
  end
  parser.on('-i', '--ignore') do |i|
    if File.file?('.directory') && File.file?('.scanned') && File.file?('.file')
      File.unlink('.directory')
      File.unlink('.scanned')
      File.unlink('.file')
      puts "Ignoring existing auto-resume files" unless super_silent
    end
  end
  parser.on('-h', '--help') do |help|
    puts "Ruby Crawler | Originally built for The Eye"
    puts "+=====================================================================================+"
    puts "+                                                                                     +"
    puts "+ -s, --silent Print only the bare minimum                                            +"
    puts "+ -S, --super_silent Print nothing                                                    +"
    puts "+ -l, --lynx Override Lynx location                                                   +"
    puts "+ -u, --url Override crawler URL. defaults to https://the-eye.eu/public/              +"
    puts "+ -e, --export Override file list output. defaults to wget. Options [wget|aria2]      +"
    puts "+ -i, --ignore Ignore auto-resume files                                               +"
    puts "+                                                                                     +"
    puts "+ This software is GPL licensed freeware. If you paid for it, demand your money back! +"
    puts "======================================================================================+"
    exit 0
  end
end.parse!

if File.file?('.directory') && File.file?('.scanned') && File.file?('.file')
  puts "Found saved session data! Importing..." unless super_silent
  # We don't bother to uniq! or sort! these because they are uniq! and sort!'d when the script exits
  File.open('.directory', 'r') { |f| f.each_line { |line| directory.push(line.strip) } }
  File.open('.scanned', 'r') { |f| f.each_line { |line| dir_scanned.push(line.strip) } }
  File.open('.file', 'r') { |f| f.each_line { |line| file.push(line.strip) } }
  # Unlinking, or removing the files to make everything nice and clean. They'll be re-written on next exit anyways
  File.unlink('.directory')
  File.unlink('.scanned')
  File.unlink('.file')
  puts "Resuming scan..." unless super_silent
else
  # Open lynx and start the initial scan
  output = Open3.popen3("#{lynx_bins} #{lynx_args} \"#{base}\" | grep \"#{base}\"") { |stdin, stdout, stderr, wait_thr| stdout.read }
  output = output.split(/\n+/)
  output.each do |out|
    # Links that we want to follow (especially on the-eye.eu) all end with a `/`. If it doesn't end like that
    # then we can safely assume it's not a directory, and instead it's a file
    if out[-1].include?("/")
      directory.push(out)
      dir_count += 1
    else
      file.push(out)
      file_count += 1
    end
  end
  # A simple calculation to make the sentence make sense. 1 files doesn't, but 1 file does
  file_name = file_count == 1 ? "file" : "files"
  dir_name = dir_count == 1 ? "directory" : "directories"
  puts "Found #{file_count} #{file_name} and #{dir_count} #{dir_name} for #{base}" unless silent || super_silent
  dir_scanned.push(base)
  sleep wait_time
end

trap "SIGINT" do
  puts ""
  puts "Saving progress, please wait..." unless  super_silent
  # We sort first, then strip away non-unique members. We have to uniq! it, as the script doesn't actively check for
  # `../` in links, it assumes that every link gathered is one we need to scan. This is not the case, and is fixed
  # in the pure ruby version
  directory.sort!.uniq!
  file.sort!.uniq!
  dir_scanned.sort!.uniq!
  File.open(".directory", "w") { |f| f.write directory.join("\n") }
  File.open(".scanned", "w") { |f| f.write dir_scanned.join("\n") }
  File.open(".file", "w") { |f| f.write file.join("\n") }
  exit 130
end

# If there are still directories to scan...
while !directory.empty?
  # Sort them...
  directory.sort!
  # Loop through them...
  directory.each do |dir|
    if ! dir_scanned.include?(dir)
      file_count = 0
      dir_count = 0
      output = Open3.popen3("#{lynx_bins} #{lynx_args} \"#{dir}\" | grep \"#{base}\"") { |stdin, stdout, stderr, wait_thr| stdout.read }
      output = output.split(/\n+/)
      sleep wait_time

      output.each do |out|
        if out[-1].include?("/")
          directory.push(out)
          dir_count += 1
        else
          file.push(out)
          file_count += 1
        end
      end
      dir_scanned.push(dir)
      if file_count != 0 || dir_count != 0
        dir_count -= 1 # Because `../` is not a valid directory
        file_name = file_count == 1 ? "file" : "files"
        dir_name = dir_count == 1 ? "directory" : "directories"
        # And tell the user what we found
        puts "Found #{file_count} #{file_name} and #{dir_count} #{dir_name} for #{dir}" unless silent || super_silent
      end
    end
    # Finally remove the directory from the stack. We don't really want to be in a loop now, do we?
    directory -= [dir]
  end
end
# Sort everything
file.sort!.uniq!
# Write it out
File.open("file_list.txt", "w") { |f| f.write dir_scanned.join("\n") } if export == "wget"
File.open("file_list.txt", "w") do |f|
  file.each do |ff|
    f.puts("#{ff}\n out=#{ff.gsub("http://the-eye.eu/", "")}")
  end
end if export == "aria2"
puts "Wrote #{file.count} file URLs to file_list.txt" unless super_silent
puts "To download with wget: wget -w #{wait_time} -x -i file_list.txt" unless super_silent || export != "wget"
puts "To download with aria2: aria2c -j 2 -m 0 --retry-wait #{wait_time} --continue -i file_list.txt" unless super_silent || export != "aria2"
# All done!