require_relative 'ann_kitsu_utils'

class Chapter
  attr_accessor :number, :title, :ja_title, :romaji_title, :date, :volume_number

  def initialize(number: '', volume_number: 0, title: '', ja_title: '', romaji_title: '', date: '')
    @number = number
    @volume_number = volume_number
    @title = title
    @ja_title = ja_title
    @romaji_title = romaji_title
    @date = date
  end

  def to_kitsu
    JSON.pretty_generate({
      # TODO a standalone chapter file

  })
  end

  def to_kitsu_hash
    data = {
      type: "Chapter",
      number: @number
    }
    data[:titles] = {
      canonical: "en",
      localized: {
        set: {
          en: @title
        }
      }
    } unless @title.empty?
    data[:titles][:localized][:set][:jp] = @ja_title unless @ja_title.empty?
    data[:titles][:localized][:set]["en-t-ja"] = @romaji_title unless @romaji_title.empty?
    data[:releasedAt] = @date unless @date.empty?
    data[:tmp_vol_num] = @volume_number

    data
  end
end

def has_japanese_characters?(str)
  !str.match(/[\p{Hiragana}\p{Katakana}\p{Han}]/).nil?
end

def parse_vol_number(td_r_text, end_of_vol = false)
  vol_match = td_r_text.match(/volume[\w\s]?[#]?(\d+)/)

  # Make sure it's not an errant comment with 'volume' in it
  if vol_match.nil? then return end

  # Check if this is an 'end [of] volume' or '[chapter title] ends'
  if td_r_text.start_with?('end') || td_r_text.end_with?('ends')
    # Make sure we aren't misaligned with volume number
    unless @volume_num == vol_match[1].to_i
      if options[:verbose]
        puts 'volume number mismatch!'
        puts chapter.number, chapter.title, chapter.date
        puts "@volume_num: #{@volume_num}, vol_match: #{vol_match}"
        puts 'Attempting to correct. Previous volume numbers possibly incorrect!'
        puts "Correcting volume number to: #{vol_match[1]}"
      end
      @volume_num = vol_match[1].to_i
    end

    # Set end_of_vol to 'true' in return as we need to keep the current vol num as is
    true
  else
    # Presume it's a demarcation of a new volume number
    unless vol_match[1].to_i < @volume_num
      @volume_num = vol_match[1].to_i
      end_of_vol
    end
  end
end

def parse_chapters(chapter_page)
  chapters = []
  # Extract the chapter table rows
  chapters_info = chapter_page.css('.episode-list tbody tr')
  # Sometimes it's marked as only a volume ending, therefore we need to keep the current volume number until the next
  # chapter/loop
  end_of_vol = false

  chapters_info&.each do |row|
    chapter = Chapter.new()

    row.css('td')&.each do |td|
      if end_of_vol
        @volume_num += 1
        end_of_vol = false
      end

      case td['class']
      when 'd'
        chapter.date = td.text.strip unless td.text.strip.empty?
      when 'n'
        chapter.number = td.text[0...-1]
      when 'pn'
        chapter.number += '.' + td.text.strip unless td.text.strip.empty?
      end

      # Contains Japanese title, romaji title and additional info like end [of] volume n
      if td['valign'] == 'top'
        chapter.title = td.at_css('div')&.text.strip || ''

        japanese_text = td.css('.j').children.css('div').map { |j| j.text.strip } rescue []
        # Japanese and romaji are under the same div in unnamed divs within class 'j'
        japanese_text.each do |jav|
          if has_japanese_characters?(jav)
            chapter.ja_title = jav
          else
            chapter.romaji_title = jav
          end
        end

        # Parse comments (class 'r') for demarcation of volume end/start
        td.at_css('.r')&.children&.each do |r|
          td_r_text = r&.text&.strip&.downcase || ''
          if td_r_text.include?('volume')
            # To work around edge case of:
            # 'End of Volume 3.'
            # 'Extra chapter included with volume 3'
            # from e.g. Fullmetal Alchemist, pass in current end_of_vol value
            end_of_vol = parse_vol_number(td_r_text, end_of_vol)
          end
        end
      end
    end
    chapter.volume_number = @volume_num
    chapters.push(chapter)
  end
  chapters
end

def load_page(base_url, subpage, myparser)
  sub_url = "#{base_url}&page=34&subpage=#{subpage}"
  return myparser.parse_html(sub_url)
rescue StandardError => e
  puts "Failed to open URL: #{base_url}&page=34&subpage=#{subpage}. Error: #{e.message}"
end

def fetch_chapters(options, myparser)
  chapter_base_url = "https://www.animenewsnetwork.com/encyclopedia/manga.php?id=#{options[:ann_id]}&page=34"
  chapters = []
  subpage = 0
  @volume_num = 1

  loop do
    doc = load_page(chapter_base_url, subpage, myparser)
    # Find links for other chapter pages
    pages_links = doc.at('#infotype-34 p')&.css('a')&.map { |a| a['href'] } || []

    if options[:verbose]
      puts "Processing chapter subpage: #{subpage}"
    end
    chapters.concat(parse_chapters(doc))

    subpage += 1
    break if subpage > pages_links.length
  end

  chapters
end
