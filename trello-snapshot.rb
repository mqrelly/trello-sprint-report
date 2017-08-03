#!/usr/bin/env ruby

require "json"
require "net/http"

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
        JSON.parse(resp)
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

  trello = TrelloReport::TrelloGateway.new(config["apiKey"], config["userToken"])

  snapshot = TrelloReport::Snapshot.new(
    trello,
    config["listIds"],
    config["cardFieldsBlackList"],
    config["cardFieldsWhiteList"])

  puts snapshot.take.to_json
end
