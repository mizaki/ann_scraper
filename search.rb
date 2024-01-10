require_relative 'ann_kitsu_utils'
require 'amatch'
include Amatch

PERFECT_MATCH = 1
NEAR_MATCH = 0.8
PARTIAL_MATCH = 0.6

def check_year(year, result)
  # The date from Kitsu can be a year after ANN
  check_year = 0
  result_year = 0

  if year&.length == 4
    check_year = year.to_i
  else
    0
  end

  result_year_arr = result.split('-')
  result_year_arr.each do |num|
    if num.length == 4
      result_year = num.to_i
    end
  end
  if result_year && check_year
    case result_year - check_year
    when 0
      PERFECT_MATCH
    when -1, 1
      NEAR_MATCH
    when -3..-1, 2..4
      PARTIAL_MATCH
    else
      0
    end
  end
end

def search_titles(options)
  base_search_url = "https://www.animenewsnetwork.com/encyclopedia/reports.xml?id=155&type=manga&search="
  url = "#{base_search_url}#{options[:search_titles][0]}"

  search_xml = parse_xml(url)

  matches = []

  for title in options[:search_titles]
    search_xml.search('item').flat_map do |item|
      # searched_title is the full title of the series matched to search term
      item_title = item.at('searched_title')&.text || ''
      item_year = item.at('vintage')&.text || 9999

      score = title.levenshtein_similar(item_title)
      score += check_year(options[:search_year], item_year)
      if score == 2
        # Perfect match for title and year
        if options[:verbose]
          puts "Perfect score for #{item_title} (#{item_year}) with ANN ID: #{item.at('id')&.text}"
        end
        return item.at('id')&.text.to_i
      end
      if score > 0.7
        matches.push({'id': item.at('id')&.text.to_i, 'score': score, 'title': item_title, 'year': item_year})
      end
    end
  end

  if options[:verbose]
    puts matches
  end

  if !matches.empty?
    matches.max_by { |result| result[:score] }[:id]
  else
    nil
  end
end
