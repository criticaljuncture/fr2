# allow api endpoints to serve csv if they support it
require 'csv'
class ApiController < ApplicationController
  class RequestError < StandardError; end
  class UnknownFieldError < RequestError; end

  before_filter :set_cors_headers
  before_filter :enforce_maximum_per_page

  private

  def set_cors_headers
    headers['Access-Control-Allow-Origin'] = '*'
  end

  def enforce_maximum_per_page
    params.delete(:maximum_per_page)
  end

  def render_json_or_jsonp(data, options = {})
    callback = params[:callback].to_s
    if callback =~ /^[a-zA-Z0-9_\.]+$/
      render({:text => "#{callback}(" + data.to_json + ")", :content_type => "application/javascript"}.merge(options))
    else
      render({:json => data.to_json}.merge(options))
    end
  end

  def render_search(search, options={}, metadata_only="0")
    if ! search.valid?
      cache_for 1.day
      render_json_or_jsonp({:errors => search.validation_errors}, :status => 400)
      return
    end

    data = { :count => search.count, :description => search.summary }

    unless metadata_only == "1"
      results = search.results(options)

      if search.count > 0 && results.count > 0
        data[:total_pages] = results.total_pages

        if results.next_page
          data[:next_page_url] = index_url(params.merge(:page => results.next_page))
        end

        if results.previous_page
          data[:previous_page_url] = index_url(params.merge(:page => results.previous_page))
        end

        data[:results] = results.map do |result|
          yield(result)
        end
      end
    end

    render_json_or_jsonp(data)
  end

  def render_one_or_more(model, document_numbers_or_citations, find_options={}, &block)
    if document_numbers_or_citations =~ /FR/
      data = render_via_citations(model, document_numbers_or_citations, find_options, &block)
    else
      data = render_via_document_numbers(model, document_numbers_or_citations, find_options, &block)
    end

    render_json_or_jsonp data
  end

  def render_via_document_numbers(model, document_numbers, find_options={}, &block)
    if document_numbers =~ /,/
      document_numbers = document_numbers.split(',')
      records = model.all(find_options.merge(
        :conditions => {:document_number => document_numbers}
      ))

      data = {
        :count => records.count,
        :results => records.map{|record| yield(record)}
      }

      missing = document_numbers - records.map(&:document_number)
      if missing.present?
        data[:errors] = {:not_found => missing}
      end
    else
      record = model.find_by_document_number!(document_numbers)
      data = yield(record)
    end

    data
  end

  def render_via_citations(model, citations, find_options={}, &block)
    if citations =~ /,/
      citations = citations.split(',')
    else
      citations = Array(citations)
    end

    records = []
    matched_citations = []
    citations.each do |citation|
      volume, fr_str, page = citation.split(' ')
      matches = model.all(find_options.merge(
        :conditions => ["volume = ? AND start_page <= ? AND end_page >= ?", volume.to_i, page.to_i, page.to_i]
      ))

      if matches.present?
        matched_citations << citation
        records << matches
      end
    end
    records.flatten!

    data = {
      :count => records.count,
      :results => records.map{|record| yield(record)}
    }

    missing = citations - matched_citations
    if missing.present?
      data[:errors] = {:not_found => missing}
    end

    data
  end

  def specified_fields
    if params[:fields]
      params[:fields].reject(&:blank?).map{|f| f.to_s.to_sym}
    end
  end

  rescue_from Exception, :with => :server_error if RAILS_ENV == 'production' || RAILS_ENV == 'staging'
  def server_error(exception)
    notify_honeybadger(exception)
    render :json => {:status => 500, :message => "Internal Server Error"}, :status => 500
  end

  rescue_from ApiRepresentation::FieldNotFound, :with => :field_not_found
  def field_not_found(exception)
    render :json => {:status => 400, :message => exception.message}, :status => 400
  end

  rescue_from RequestError, :with => :request_error if RAILS_ENV != 'development'
  def request_error(exception)
    render :json => {:status => 400, :message => exception.message}, :status => 400
  end

  rescue_from ActiveRecord::RecordNotFound, :with => :record_not_found if RAILS_ENV != 'development'
  def record_not_found
    render :json => {:status => 404, :message => "Record Not Found"}, :status => 404
  end

  rescue_from ActionController::MethodNotAllowed, :with => :method_not_allowed if RAILS_ENV != 'development'
  def method_not_allowed
    render :json => {:status => 405, :message => "Method Not Allowed"}, :status => 405
  end
end
