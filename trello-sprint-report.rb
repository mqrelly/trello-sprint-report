#!/usr/bin/env ruby
require "json"
require "date"
require "erb"
require "optparse"

module TrelloReport

  class Snapshot
    def self.load(file_name)
      Snapshot.new(JSON.parse(File.read(file_name)))
    end

    def initialize(data)
      @data = data

      fill_in_list_names
    end

    def timestamp
      @timestamp ||= Date.parse(@data["timestamp"])
    end

    def lists
      @data["lists"]
    end

    def cards
      @cards ||= lists
        .map{|lst| lst["cards"]}
        .flatten(1)
    end

    def all_card_ids
      @all_card_ids ||= cards.map{|crd| crd["id"]}
    end

    def card(card_id)
      @data["lists"].each do |lst|
        lst["cards"].each do |crd|
          return crd if crd["id"] == card_id
        end
      end

      nil
    end

    def labels
      @labels ||= @data["lists"]
        .map{|lst| lst["cards"].map{|crd| crd["labels"]}}
        .flatten(2)
        .uniq{|lbl| lbl["id"]}
    end

    def all_label_ids
      labels.map{|lbl| lbl["id"]}
    end

    def label(label_id)
      labels.select{|lbl| lbl["id"] == label_id}.first
    end

    def cards_with_label(label_id)
      cards.select{|crd| crd["labels"].any?{|lbl| lbl["id"] == label_id}}
    end

    private

    def fill_in_list_names
      @data["lists"].each do |lst|
        lst["cards"].each do |crd|
          crd["list-name"] = lst["name"]
          crd["state"] = "in-progress"
        end
      end
    end
  end

  class SprintReport

    def initialize(start_snapshot, end_snapshot, template_file)
      @start_sp = start_snapshot
      @end_sp = end_snapshot

      @template = ERB.new(File.read(template_file))
      @template.filename = template_file

      fill_in_card_states
    end

    def start_date
      @start_sp.timestamp
    end

    def end_date
      @end_sp.timestamp
    end

    def sprint_days
      (end_date - start_date).to_i + 1
    end

    def lists
      @end_sp.lists
    end

    def all_card_ids
      (@end_sp.all_card_ids + @start_sp.all_card_ids).uniq
    end

    def incoming_card_ids
      @end_sp.all_card_ids - @start_sp.all_card_ids
    end

    def abandoned_card_ids
      @start_sp.all_card_ids - @end_sp.all_card_ids
    end

    def card(card_id)
      @end_sp.card(card_id) || @start_sp.card(card_id)
    end

    def all_label_ids
      (@end_sp.all_label_ids + @start_sp.all_label_ids).uniq
    end

    def label(label_id)
      @end_sp.label(label_id) || @start_sp.label(label_id)
    end

    def cards_with_label(label_id)
      (@end_sp.cards_with_label(label_id) + @start_sp.cards_with_label(label_id))
        .uniq{|crd| crd["id"]}
    end

    def data_as_json
      data = {
        :labels => all_label_ids.map{|id| label(id)},
        :cards => all_card_ids.map{|id| card(id)}
      }

      data.to_json
    end

    def generate
      @template.result binding
    end

    private

    def fill_in_card_states
      lists.last["cards"].each do |crd|
        crd["state"] = "done"
      end

      abandoned_card_ids.each do |id|
        card(id)["state"] = "abandoned"
      end

      incoming_card_ids.each do |id|
        card(id)["is_incoming"] = true
      end
    end
  end

end

def locate_template(name)
  name ||= "default.html.erb"

  search_dirs = [
    ".",
    File.join(File.dirname(__FILE__), "templates")
  ]

  search_dirs.each do |dir|
    file = File.join File.expand_path(dir), name
    return file if File.exists? file

    file += ".erb"
    return file if File.exists? file
  end

  throw "Couldn't find report template '#{name}'."
end

if $0 == __FILE__

  options = {}

  optionParser = OptionParser.new do |opts|
    opts.on("-sFILE",
            "--start-snapshot=FILE",
            "Snapshot of the board at the beginning of the sprint.") do |start_file|
      options[:start_file] = start_file
    end

    opts.on("-eFILE",
            "--end-snapshot=FILE",
            "Snapshot of the board at the end of the sprint.") do |end_file|
      options[:end_file] = end_file
    end

    opts.on("-tFILE",
            "--template=FILE",
            "Optional template for report generation. [simple.html.erb]") do |template_file|
      options[:template_file] = template_file
    end
  end
  optionParser.parse!

  if options[:start_file].nil?
    puts "Missing start snapshot parameter!"
    puts optionParser
    exit 1
  end

  if options[:end_file].nil?
    puts "Missing end snapshot parameter!"
    puts optionParser
    exit 1
  end

  start_snapshot = TrelloReport::Snapshot.load(options[:start_file])
  end_snapshot = TrelloReport::Snapshot.load(options[:end_file])
  template_file = locate_template(options[:template_file])

  report = TrelloReport::SprintReport.new start_snapshot, end_snapshot, template_file
  puts report.generate

end
