class EsEntrySearch::DateAggregator::Base
  extend Memoist

  def initialize(es_search, options)
    @es_search = es_search
    if options[:with] && options[:with][:publication_date]
      @start_date = Time.at(options[:with][:publication_date].first).utc.to_date

      end_date = Time.at(options[:with][:publication_date].last).utc.to_date
      @end_date = end_date > Issue.current.publication_date ? Issue.current.publication_date : end_date
    else
      @start_date = Date.new(1994,1,1)
      @end_date = Issue.current.publication_date
    end
  end

  def counts
    periods.map{|sub_periods| sub_periods.map{|p| raw_results[sphinx_format(p)] || 0}.sum }
  end

  def results
    periods.each_with_object(Hash.new) do |sub_periods, hsh|
      identifier = sub_periods.first
      hsh[identifier.to_s(:iso)] = {
        :count => sub_periods.map{|p| raw_results[sphinx_format(p)] || 0}.sum,
        :name => name_format(identifier)
      }
    end
  end

  def raw_results
    group_and_counts = {}
    es_search.date_aggregator_buckets.map do |term|
      datetime = Date.parse(term['key_as_string']) #TODO: Do we need to handle UTC processing parallel to what's happening in the Sphinx-based base.rb class?

      group_and_counts[sphinx_format(datetime)] = term.doc_count
    end

    group_and_counts
  end
  memoize :raw_results

  private

  attr_reader :es_search

  def sphinx_format(date)
    date.strftime(sphinx_format_str)
  end

  def name_format(date)
    date.strftime(name_format_str)
  end

end
