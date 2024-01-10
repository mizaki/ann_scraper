require 'optparse'
require_relative 'fetch_manga'
require_relative 'search'

options = {:inc_vol=>true, :inc_chap=>true, :out_type=> "kitsu"}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby ann_scraper.rb [options]
  A TITLE or ANN ID is required.
  Title(s) will be searched and the best resulted used (within a threshold)."

  opts.on("-t TITLE", "--titles", String, "A manga series title (English/Romaji/Japanese). Single or comma separated within quotes, e.g. \"Naruto\" or \"My Hero Academia, 僕のヒーローアカデミア, Boku no Hero Academia\"") do |title|
    options[:search_titles] = title.split(',').map(&:strip)
  end

  opts.on("-a", "--ann ID", Integer, "The number ID for the manga series on ANN") do |aid|
    options[:ann_id] = aid
  end

  opts.on("-y", "--year YEAR", String, "A four digit start year for the manga series") do |year|
    options[:search_year] = year
  end

  opts.on("-o", "--output TYPE", String, "JSON output type: \"common\", \"kitsu\" (Default: kitsu)") do |out_type|
    options[:out_type] = out_type
  end

  opts.on("-k", "--kitsu ID", Integer, "The number ID for the manga series on Kitsu.io. REQUIRED FOR UPDATING!") do |kid|
    options[:kitsu_id] = kid
  end

  opts.on("--no-volume", "Do not include volume information for manga") do |inc_vol|
    options[:inc_vol] = inc_vol
  end

  opts.on("--no-chapter", "Do not include chapter information for manga") do |inc_chap|
    options[:inc_chap] = inc_chap
  end

  opts.on("-v", "--verbose", "Print information to the commandline") do |verbose|
    options[:verbose] = verbose
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

# TODO if adding chapter/volume only, a Kitsu manga ID will be required
unless options[:search_titles] || options[:ann_id]
  puts "Error: At least one search title is required (English, Romaji or Japanese) OR an ANN manga ID."
  puts "See -h or --help for usage information."
  exit 1
end

if options[:ann_id]
  fetch_manga(options)
else
  options[:ann_id] = search_titles(options)
  if options[:ann_id]
    fetch_manga(options)
  else
    puts 'No ANN ID found'
    exit
  end
end
