#!/usr/bin/env ruby
require "json"
require "date"
require "erb"

class Snapshot
  def self.load(file_name)
    sp = Snapshot.new(JSON.parse(File.read(file_name)))
  end

  def initialize(data)
    @data = data
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
end

class SprintReport

  #incoming_card_ids = end_snapshot.all_card_ids - start_snapshot.all_card_ids
  #abandoned_card_ids = start_snapshot.all_card_ids - end_snapshot.all_card_ids

  def initialize(start_snapshot, end_snapshot, template_file)
    @start_sp = start_snapshot
    @end_sp = end_snapshot

    @template = ERB.new(File.read(template_file))
    @template.filename = template_file
  end

  def start_date
    @start_sp.timestamp
  end

  def end_date
    @end_sp.timestamp
  end

  def sprint_days
    (end_date - start_date).to_i
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

  def generate
    @template.result binding
  end
end

if ARGV.length != 2
  puts "Usage: $ trello-sprint-report.rb <start-snapshot-file> <stop-snapshot-file>"
  puts "  The output will be the report in HTML format on the stdout."
  exit 1
end

start_snapshot = Snapshot.load(ARGV[0])
end_snapshot = Snapshot.load(ARGV[1])
template_file = "report.html.erb"

report = SprintReport.new start_snapshot, end_snapshot, template_file
puts report.generate
