require_relative 'ann_kitsu_utils'

class Volume
  attr_accessor :release_id, :title, :pages, :distributor, :image,
                :release_date, :desc, :price, :m_rating, :volume_number,
                :isbn10, :isbn13, :sku

  def initialize(release_id:, title: "", pages: 0, distributor: "", image: "",
                 release_date: "", desc: "", m_rating: "", volume_number: 0,
                 isbn10: "", isbn13: "", sku: "", price: "")
    @release_id = release_id
    @title = title
    @pages = pages
    @distributor = distributor
    @image = image
    @release_date = release_date
    @desc = desc
    @price = price
    @m_rating = m_rating
    @volume_number = volume_number
    @isbn10 = isbn10
    @isbn13 = isbn13
    @sku = sku
  end

  def to_kitsu
    # TODO a standalone volume file
    data = {
      type: 'Volume',
      number: @volume_number,
    }
    data[:titles] = {
      canonical: "en",
      localized: {
        set: {
          en: @title
        }
      }
    } unless @title.empty?
    data[:publishedAt] = @release_date unless @release_date.empty?
    data[:isbn] = @isbn10 unless @isbn10.empty?

    JSON.pretty_generate(data)
  end

  def to_kitsu_hash
    data = {
      type: 'Volume',
      number: @volume_number,
    }
    data[:titles] = {
      canonical: "en",
      localized: {
        set: {
          en: @title
        }
      }
    } unless @title.empty?
    data[:publishedAt] = @release_date unless @release_date.empty?
    data[:isbn] = @isbn10 unless @isbn10.empty?

    data
  end
end

def extract_text_recursive(node)
  if !node.key?('title') && node.text?
    text = node.text.strip
    text unless text.empty?
  elsif !node.key?('title')
    node.children.flat_map { |child| extract_text_recursive(child) }.compact
  end
end

def parse_desc(rel_list, i)
  j = 1
  desc = ""

  # Description may have multiple paragraphs and contain story and artist
  # Delimit end by '(added on'...
  while i + j < rel_list.length && !rel_list[i + j].start_with?("(added on") && !rel_list[i + j].start_with?("Story")
    desc += rel_list[i + j] + "\n"
    j += 1
  end

  desc
end

def create_release_obj(rel_list, vol_id, vol_titles, series_title)
  release = Volume.new(release_id: vol_id, image: "https://cdn.animenewsnetwork.com/thumbnails/area200x300/releases/#{vol_id}.jpg")
  for rel, i in rel_list.each_with_index
    case rel
    when 'Description:'
      release.desc = parse_desc(rel_list, i)
    when 'Volume:'
      # Some volume "numbers" are "GN" only (where there is only 1), so assume they are 1
      # Might be a multi-volume, check for hyphen after GN? Kitsu only allows int for number
      release.volume_number = (rel_list[i+1].match(/(\d+)/)&.[](1) || '1').to_i
    when 'Title:'
      # This may contain the volume title after the series title, e.g. "<Manga title> - <Volume title>"
      # May also use [] for hardcover etc., currently ignored
      poss_title = rel_list[i+1].match(/#{series_title}\W+([\w\s]+)(\[.*\])?/)
      unless poss_title.nil?
        release.title = poss_title[1].strip
      end
    # eBooks have 'Running time' for pages
    when 'Running time:', 'Pages:'
      release.pages = rel_list[i+1]
    when 'Distributor:'
      release.distributor = rel_list[i+1]
    when 'Release date:'
      rel_date = rel_list[i+1]
      release.release_date = rel_list[i+1]
    when 'Suggested retail price:'
      release.price = rel_list[i+1]
    when 'Age rating:'
      release.m_rating = rel_list[i+1]
    when 'ISBN-10:'
      release.isbn10 = rel_list[i+1]
    when 'ISBN-13:'
      release.isbn13 = rel_list[i+1]
    when 'SKU:'
      release.sku = rel_list[i+1]
    end
  end
  if !vol_titles.empty?
    release.title = vol_titles[release.volume_number] if vol_titles[release.volume_number]
  end
  release
end

def fetch_volume(options, vol_url, vol_titles, series_title, myparser)
  # Grab vol ID from URL
  vol_id = vol_url.match(/id=(\d+)/)[1].to_i

  if options[:verbose]
    puts "Processing volume release ID: #{vol_id}"
  end

  doc = myparser.parse_html(vol_url)
  release_info = doc.at('#content-zone div')
  # Remove A-Z navigation links
  release_info.css('center').remove
  text_elements = release_info.children.flat_map { |child| extract_text_recursive(child) }.compact

  create_release_obj(text_elements, vol_id, vol_titles, series_title)
end
