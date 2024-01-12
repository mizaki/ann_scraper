require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'ruby-limiter'
require 'json'
require 'date'

def format_date(date_string)
  case date_string.length
  when 4
    date_string += '-01-01'
  when 7
    date_string += '-01'
  when 10
    date_string
  else
    date_string = ''
  end
end

# @params [String] An XML string may contain HTML formatting (e.g. Alice 19<sup>th</sup>) so remove
# @return [String]
def clean_text(text)
  Nokogiri::HTML.fragment(text).text
end

# From https://www.animenewsnetwork.com/encyclopedia/api.php
# "The API is rate-limited to 1 request per second per IP address; requests over this threshold will be delayed. If you
# would rather make 5 requests close together every 5 seconds, use nodelay.api.xml instead; but requests over the 1/s
# threshold will get a 503 error."
class Parser
  extend Limiter::Mixin

  limit_method(:parse_xml, rate: 1, interval: 1) do
  end

  limit_method(:parse_html, rate: 1, interval: 1) do
  end

  def parse_xml(url)
    begin
      Nokogiri::XML(URI.open(url))
    rescue StandardError => e
      puts "Failed to open URL: #{url}. Error: #{e.message}"
      exit
    end
  end

  def parse_html(url)
    begin
      Nokogiri::HTML(URI.open(url))
    rescue StandardError => e
      puts "Failed to open URL: #{url}. Error: #{e.message}"
      exit
    end
  end
end

def old_file?(file_path, days = 7)
  file_mtime = File.mtime(file_path)
  diff_secs = Time.now - file_mtime
  diff_days = diff_secs / (24 * 60 * 60)
  diff_days > days
end

def kitsu_gql(query)
  url = URI.parse('https://kitsu.io/api/graphql')
  data = { query: query }
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = (url.scheme == 'https')

  request = Net::HTTP::Post.new(url.path, 'Content-Type' => 'application/json')
  request.body = data.to_json

  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  else
    false
  end
end

# @param [None] Downloads and writes Kitsu category titles and IDs to file: data/cats.json
# @return [Bool] New file written true/false
def download_cats()
  cats_query = <<-GRAPHQL
  query getCats {
    categories(first:1000) {
      nodes {
        id
        title(locales:["*"])
      }
      pageInfo {
        hasNextPage
      }
      totalCount
    }
  }
  GRAPHQL

  json_data = kitsu_gql(cats_query)
  cats = json_data&.dig('data', 'categories', 'nodes')
  if cats
    File.open('data/cats.json', 'w') do |file|
      file.puts cats.to_json
      true
    end
  else
    false
  end
end

def load_cats()
  cats_file = 'data/cats.json'

  if !File.exist?(cats_file) || old_file?(cats_file)
    download_cats()
  end

  begin
    @kitsu_categories = JSON.parse(File.read(cats_file))
  rescue
    []
  end
end

# @param [String] Map a category to a Kitsu category ID
# @return [String] Kitsu ID number
def cat_id_by_title(search_title)
  load_cats unless @kitsu_categories
  match = @kitsu_categories.find { |cats| cats["title"]["en"].downcase == search_title }
  if match
    match["id"]
  end
end

# @param [Integer] Map an ANN ID to a name
# @return [String] Manga publication name: Weekly Shonen Jump, Shonen Gangan, Hana to Yume, etc.
def ann_serial_by_id(ann_id, myparser)
  doc = myparser.parse_xml("https://cdn.animenewsnetwork.com/encyclopedia/api.xml?manga=#{ann_id}")
  manga = doc.at('manga')
  unless manga['name'].empty? || manga.at('warning')
    manga['name']
  end
end

# @param [String] ann_rating ANN rating to be mapped. See https://www.animenewsnetwork.com/bbs/phpBB2/viewtopic.php?p=907831#907831
# @return [String] Kitsu rating system: "G","PG","R","R18"
def ann_rating_map(ann_rating)
  case ann_rating
  when 'None', 'AA' then 'G'
  when 'Mild', 'OC' then 'PG'
  when 'Significant', 'Intense', 'TA', 'MA' then 'R'
  when 'Pornography', 'AO' then 'R18'
  else
    'Unknown'
  end
end
