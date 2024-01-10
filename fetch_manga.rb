require 'json'
require 'benchmark'
require_relative 'fetch_volume'
require_relative 'fetch_chapters'
require_relative 'ann_kitsu_utils'

@base_manga_url = 'https://cdn.animenewsnetwork.com/encyclopedia/api.xml?manga='
@kitsu_categories = nil
@vol_titles = {}

class Manga
  attr_accessor :ann_id, :kitsu_id, :title, :image, :genres, :themes, :desc, :alt_titles,
                :m_rating, :chapter_count, :chapters, :volume_count, :volumes,
                :pages, :start_date, :end_date, :rating, :volume_urls,
                :writer, :artist, :loc_titles, :serialised, :related_anime

  def initialize(ann_id:, title: "", kitsu_id: nil, image: "", genres: [], themes: [], desc: "",
                 alt_titles: [], m_rating: "", chapter_count: 0, chapters: [],
                 volume_count: 0, volumes: [], pages: 0, start_date: "", loc_titles: [],
                 end_date: "", rating: 0, volume_urls: [], writer: "", artist: "",
                 serialised: [], related_anime: [])
    @ann_id = ann_id
    @kitsu_id = kitsu_id
    @title = title
    @image = image
    @genres = genres
    @themes = themes
    @desc = desc
    @alt_titles = alt_titles
    @loc_titles = loc_titles
    @m_rating = m_rating
    @chapter_count = chapter_count
    @chapters = chapters
    @volume_count = volume_count
    @volumes = volumes
    @pages = pages
    @start_date = start_date
    @end_date = end_date
    @serialised = serialised
    @rating = rating
    @volume_urls = volume_urls
    @writer = writer
    @artist = artist
    @related_anime = related_anime
  end

  def to_json(*args)
    JSON.pretty_generate({
      ann_id: @ann_id,
      kitsu_id: @kitsu_id,
      title: @title,
      image: @image,
      genres: @genres,
      themes: @themes,
      desc: @desc,
      alt_titles: @alt_titles,
      loc_titles: @loc_titles,
      m_rating: @m_rating,
      chapter_count: @chapter_count,
      volume_count: @volume_count,
      pages: @pages,
      start_date: @start_date,
      end_date: @end_date,
      rating: @rating,
      volume_urls: @volume_urls,
      writer: @writer,
      artist: @artist,
      chapters: @chapters,
      volumes: @volumes
    })
  end

  def to_kitsu
    data = {
      type: 'manga',
      mappings: {
        set: {
          "animenewsnetwork": @ann_id
        }
      }
    }
    data[:id] = @kitsu_id unless @kitsu_id.nil?
    data[:titles] = {
      canonical: "en",
      localized: {
        set: {
          en: @title
        }.merge(@loc_titles.map { |hash| hash.transform_keys(&:to_s) }.reduce({}, :merge)).compact
      }
    } unless @title.empty?
    data[:titles]['alternatives'] = @alt_titles unless @alt_titles.empty?
    data[:startDate] = @start_date unless @start_date.empty?
    data[:endDate] = @end_date unless @end_date.empty?
    data[:ageRating] = ann_rating_map(@m_rating) unless @m_rating.empty?
    data[:categories] = {
      add: @genres.concat(@themes).map { |cat|
        {
          type: "Category",
          id: cat_id_by_title(cat) || next
        }
      }.compact
    } unless @genres.empty? && @themes.empty?
    data[:productions] = {
      add: @serialised.map { |serial|
        {
          type: "Production",
          role: "serialization",
          producer: {
            type: "Producer",
            name: ann_serial_by_id(serial) || next
          }
        }
      }.compact
    } unless @serialised.empty?
    data[:chapters] = {
      add: [ @chapters.map(&:to_kitsu_hash).compact ]
    } unless @chapters.empty?
    data[:description] = {
      set: {
        "en": @desc + ' Via ANN' # Add ANN URL?
      }
    } unless @desc.empty?
    data[:volumes] = {
      add: [ @volumes.map(&:to_kitsu_hash).compact ]
    } unless @volumes.empty?
    data[:chapterCount] = @chapter_count unless @chapter_count == 0
    data[:volumeCount] = @volume_count unless @volume_count == 0
    data[:staff] = { # TODO when finalised for kitsu
      add: [
        {
          writer: @writer,
          artist: @artist
        }
      ].compact
    } unless @writer.empty? && @artist.empty?

    JSON.pretty_generate(data)
  end
end

def fetch_vol_titles(id)
  # For some reason the volume names are sometimes on the main series page (and not in XML)
  page = parse_html("https://www.animenewsnetwork.com/encyclopedia/manga.php?id=#{id}")
  # '#infotype-20' is the ID for the volume names
  page.css('#infotype-20').children.each do |vol_title|
    match = vol_title&.text.match(/(\d+)\.(.*)/)
    if match
      @vol_titles.merge!({match[1]&.to_i=> match[2].strip})
    end
  end
end

def fetch_manga(options)
  url = "#{@base_manga_url}#{options[:ann_id]}"

  manga = Manga.new(ann_id: options[:ann_id])

  doc = parse_xml(url)

  if doc.at('warning')
    puts "Problem with ID: #{options[:ann_id]} - #{doc.at('warning').text}"
    exit
  end

  result = Benchmark.measure do
    doc.search('info').each do |k|
      case k['type']
      when 'Alternative title'
        # Any additional 'en' we'll send as alts
        # There are some langague titles that are 'EN' but aren't, e.g.
        # <info gid="2022235289" type="Alternative title" lang="EN">Giả Kim Thuật Sư (Vietnamese)</info>
        # What to do with them?
        if k['lang'] == 'EN'
          manga.alt_titles.push(clean_text(k.text))
        else
          manga.loc_titles.push({k['lang'].downcase.to_sym => clean_text(k.text)})
        end
      when 'Picture'
        # Last src should be largest image
        manga.image = k.last_element_child['src']
      when 'Main title'
        manga.title = clean_text(k.text)
      when 'Genres'
        manga.genres.push(k.text)
      when 'Themes'
        manga.themes.push(k.text)
      when 'Objectionable content'
        manga.m_rating = k.text
      when 'Plot Summary'
        manga.desc = k.text
      when 'Number of tankoubon'
        manga.volume_count = k.text.to_i
      when 'Number of pages'
        manga.pages = k.text.to_i
      when 'Vintage'
        # Take the first date
        if manga.start_date.empty?
          vintage = k.text.split('(')[0].split('to').map(&:strip)
          vintage.map! { |vint|
            vint = format_date(vint)
          }
          manga.start_date = vintage[0]
          # end_date can be empty
          manga.end_date = vintage[1] if vintage[1]
        else
          next
        end
      end
    end

    # Won't be used for kitsu but grab them anyway
    ratings = doc.at('ratings')
    manga.rating = ratings['bayesian_score']&.to_f if !ratings.nil?

    doc.search('release').each do |rel|
      # Only extract GN for later volume data scrape. TODO Should do eBooks too?
      if rel.text.include?('GN')
        manga.volume_urls.push(rel['href'])
      end
    end

    doc.search('staff').each do |staff|
      case staff.at('task').text
        when 'Story & Art'
          manga.writer = staff.at('person').text
          manga.artist = staff.at('person').text
        when 'Story'
          manga.writer = staff.at('person').text
        when 'Art'
          manga.artist = staff.at('person').text
      end
    end

    # Array of ANN IDs for serialised publication
    manga.serialised = doc.css('manga related-prev[rel="serialized in"]').map { |rel| rel['id'] }
    # Array of ANN IDs and type (adaptation, spinoff, etc.) for related anime
    manga.related_anime = doc.css('manga related-next').map { |rel| { :ann_id=>rel['id'], :type=>rel['rel'] } }

    # Fetch chapters info
    if options[:inc_chap]
      manga.chapters.concat(fetch_chapters(options[:ann_id]))
      manga.chapter_count = manga.chapters.length
    end

    # Fetch volumes info
    unless manga.volume_urls.empty? || !options[:inc_vol]
      fetch_vol_titles(options[:ann_id])
      manga.volume_urls.each do | url |
        manga.volumes.push(fetch_volume(options, url, @vol_titles, manga.title))
      end
    end

    if options[:kitsu_id]
      manga.kitsu_id = options[:kitsu_id]
    end

    if options[:out_type] == 'kitsu'
      file_path = "output/#{options[:ann_id]}_kitsu.json"
      output_type = 'to_kitsu'
    elsif options[:out_type] == 'common'
      file_path = "output/#{options[:ann_id]}.json"
      output_type = 'to_json'
    end

    File.open(file_path, 'w') do |file|
      file.puts manga.send(output_type)
      puts "Output file: #{file_path}"
    end
  end

  if options[:verbose]
    puts "Finished manga download for ANN ID: #{manga.ann_id} Title: #{manga.title}, Volumes: #{manga.volume_count}, Chapters: #{manga.chapter_count}"
    puts "Took: #{result.real} seconds"
  end
end
