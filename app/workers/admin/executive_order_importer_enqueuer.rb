class Admin::ExecutiveOrderImporterEnqueuer
  include ExecutiveOrderImportUtils

  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options :queue => :api_core, :retry => 0

  def perform(file_path, file_identifier)
    begin
      Content::ExecutiveOrderImporter.perform(file_path)
      ElasticsearchIndexer.handle_entry_changes
      CacheUtils.purge_cache(".*")
      record_job_status(file_identifier, 'complete')
    rescue StandardError => e
      record_job_status(file_identifier, 'failed')
      raise e
    end
  end

end
