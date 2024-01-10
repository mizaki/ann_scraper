# Anime News Nework scraper

A commandline Ruby script to scrape [Anime News Network](https://www.animenewsnetwork.com) for manga (volume/chapter) information and format into JSON (compatible with [kitsu.io](https://kitsu.io))

## Run
`ruby ann_scraper.rb <options>`

## Help
```
Usage: ruby ann_scraper.rb [options]
  A TITLE or ANN ID is required.
  Title(s) will be searched and the best resulted used (within a threshold).
    -t, --titles TITLE               A manga series title (English/Romaji/Japanese). Single or comma separated within quotes, e.g. "Naruto" or "My Hero Academia, 僕のヒーローアカデミア, Boku no Hero Academia"
    -a, --ann ID                     The number ID for the manga series on ANN
    -y, --year YEAR                  A four digit start year for the manga series
    -o, --output TYPE                JSON output type: "common", "kitsu" (Default: kitsu)
    -k, --kitsu ID                   The number ID for the manga series on Kitsu.io. REQUIRED FOR UPDATING!
        --no-volume                  Do not include volume information for manga
        --no-chapter                 Do not include chapter information for manga
    -v, --verbose                    Print information to the commandline
    -h, --help                       Prints this help
```