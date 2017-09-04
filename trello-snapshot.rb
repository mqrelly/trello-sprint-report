#!/usr/bin/env ruby

require "json"
require "net/http"
require "optparse"

module TrelloReport

  class TrelloGateway
    def initialize(api_key, user_token)
      @api_key = api_key
      @user_token = user_token
    end

    def get_list_name(list_id)
      url = api_url_for_list("name", list_id)
      resp = make_http_request(url)
      resp["_value"]
    end

    def get_list_cards(list_id)
      url = api_url_for_list("cards", list_id)
      resp = make_http_request(url)
      resp
    end

    private

    def api_url_for_list(part, list_id)
      "https://api.trello.com/1/lists/#{list_id}/#{part}?key=#{@api_key}&token=#{@user_token}"
    end

    def make_http_request(url)
      resp = Net::HTTP.get(URI(url))
      begin
        JSON.parse(resp)
      rescue JSON::ParserError
        STDERR.puts "Failed to make a request to Trello:"
        STDERR.puts resp
        exit 1
      end
    end
  end

  class Snapshot
    def initialize(trello, list_ids, field_black_list, field_white_list)
      @trello = trello
      @list_ids = list_ids
      @field_black_list = field_black_list
      @field_white_list = field_white_list
    end

    def take
      @sp if @sp

      @sp = {}
      @sp["timestamp"] = Time.now.utc.strftime("%FT%T%:z")
      @sp["lists"] = @list_ids.map{|lid| get_list_snapshot(lid)}

      @sp
    end

    private

    def get_list_snapshot(list_id)
      {
        "id" => list_id,
        "name" => @trello.get_list_name(list_id),
        "cards" => get_list_cards(list_id)
      }
    end

    def get_list_cards(list_id)
      @trello
        .get_list_cards(list_id)
        .map{|crd| filter_card_data(crd)}
    end

    def filter_card_data(card)
      card.reject!{|f,_| @field_black_list.include? f} if @field_black_list
      card.select!{|f,_| @field_white_list.include? f} if @field_white_list
      card
    end
  end

end

if $0 == __FILE__

  config = JSON.parse(File.read("trello-snapshot-config.json"))

  optionParser = OptionParser.new do |opts|
    opts.on("-kKEY",
            "--trello-api-key=KEY",
            "Optional Trello API Key, overwrites the one in the config file.") do |api_key|
              config["apiKey"] = api_key
            end

    opts.on("-tTOKEN",
            "--trello-user-token=TOKEN",
            "Optional Trello User Token, overwrites the one in the config file.") do |user_token|
              config["userToken"] = user_token
            end
  end
  optionParser.parse!

  trello = TrelloReport::TrelloGateway.new(config["apiKey"], config["userToken"])

  snapshot = TrelloReport::Snapshot.new(
    trello,
    config["listIds"],
    config["cardFieldsBlackList"],
    config["cardFieldsWhiteList"])

  puts snapshot.take.to_json
end
