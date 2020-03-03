require "spec_helper"

describe "Elasticsearch Entry Search" do

  def build_entry_double(hsh)
    entry = double('entry')
    allow(entry).to receive(:to_hash).and_return(hsh)
    allow(entry).to receive(:id).and_return(hsh.fetch(:id))
    entry
  end

  let!(:entry) do
    Factory(
      :entry,
      publication_date: Date.new(2020,1,1),
      significant: 1,
    )
  end

  context "Elasticsearch query definition" do

    it "integrates a basic #with attribute" do
      search = EsEntrySearch.new(conditions: {significant: 1})

      expect(search.send(:search_options)).to eq(
        {
          from: 0,
          query: {
            bool: {
              must: [],
              filter: [
                {
                  bool: {
                    filter: {
                      term: {
                        significant: true
                      }
                    }
                  }
                }
              ]
            }
          },
          size: EsApplicationSearch::DEFAULT_RESULTS_PER_PAGE,
          sort: [{_score: {:order=>"desc"}}]
        }
      )
    end

    it "builds the expected search with multiple attributes correctly" do
      agency = Factory(:agency, slug: 'antitrust-division')

      search = EsEntrySearch.new(
        conditions: {
          presidential_document_type: ['determination', 'executive_order'],
        }
      )

      expect(search.send(:search_options)).to eq(
        {
          from: 0,
          query: {
            bool: {
              must: [],
              filter: [
                {
                  bool: {
                    filter: {
                      terms: {presidential_document_type_id: [1,2]}
                    }
                  }
                }
              ]
            }
          },
          size: EsApplicationSearch::DEFAULT_RESULTS_PER_PAGE,
          sort: [{_score: {:order=>"desc"}}]
        }
      )
    end

    it "handles less-than queries" do
      search = EsEntrySearch.new(:conditions => {:publication_date => {:gte => '2000-01-01', :lte => '2049-01-01'}})

      expect(search.send(:search_options)).to eq(
        {
          from: 0,
          query: {
            bool: {
              must: [],
              filter: [
                {
                  range: {
                    publication_date: {
                      gte: '2000-01-01',
                      lte: '2049-01-01',
                    }
                  }
                }
              ]
            }
          },
          size: EsApplicationSearch::DEFAULT_RESULTS_PER_PAGE,
          sort: [{_score: {:order=>"desc"}}]
        }
      )
    end

  end

  context "Elasticsearch retrieval" do

    before(:each) do
      $entry_repository.create_index!(force: true)
    end

    context "advanced search terms" do
      it "handles a combination of advanced search syntax" do
        entries = [
          build_entry_double({title: 'fried eggs potato', id: 777}),
          build_entry_double({full_text: 'fried eggs eggplant', id: 888}),
          build_entry_double({full_text: 'fried eggs eggplant frittata', id: 888}),
          build_entry_double({agency_name: 'frittata', id: 999}),
        ]
        Entry.bulk_index(entries)
        $entry_repository.refresh_index!

        search = EsEntrySearch.new(conditions: {term: '"fried eggs" +(eggplant | potato)'})

        expect(search.results.es_ids).to match_array([777,888])
      end
    end

    it "retrieves an Active Record-like collection" do
      another_entry = Factory(:entry, significant: 0, title: 'fish')
      entries = [
        another_entry
      ]

      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {significant: 0, term: 'fish'})
      results = search.results

      expect(results.count).to eq(1)
      expect(results.first.id).to eq(another_entry.id)
    end

    it "performs basic excerpting" do
      $entry_repository.create_index!(force: true)
      another_entry = Factory(
        :entry,
        significant: 0,
        abstract: 'fish are great.',
        title: "Fish stuff",
        raw_text: "The fish swam across the pond",
        raw_text_updated_at: Time.current
      )
      entries = [
        another_entry
      ]

      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(
        excerpts: true,
        conditions: {significant: 0, term: 'fish'}
      )

      result = search.results.first.excerpt

      expect(result).to eq("The <span class=\"match\">fish</span> swam across the pond ... <span class=\"match\">fish</span> are great. ... <span class=\"match\">Fish</span> stuff")
    end

    it "Entry.bulk_index" do
      another_entry = Factory(:entry, significant: 0, title: 'fish')
      entries = [
        another_entry
      ]

      Entry.bulk_index(entries)
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {significant: 0, term: 'fish'})
      results = search.results

      expect(results.count).to eq(1)
      expect(results.first.id).to eq(another_entry.id)
    end

    it "handles type attribute that was formerly CRC32-processed in Sphinx" do
      entries = [
        build_entry_double({type: ["RULE"], id: 111}),
      ]
      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {type: ["RULE", "NOTICE"]})

      expect(search.results.es_ids).to eq [111]
    end

    it "handles document_number attribute that was formerly CRC32-processed in Sphinx" do
      entries = [
        build_entry_double({document_number: "93-31907", id: 111}),
      ]
      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {document_numbers: ["93-31907"]})

      expect(search.results.es_ids).to eq [111]
    end

    it "retrieves the expected results for a term" do
      entries = [
        build_entry_double({title: 'fish', id: 888}),
        build_entry_double({title: 'goat', id: 999})
      ]
      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {term: 'fish'})

      expect(search.results.count).to eq 1
    end

    it "If no entries meet the criteria, count is zero" do
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {significant: 1})

      expect(search.results.count).to eq 0
    end

    it "applies a basic boolean filter correctly" do
      entries = [
        build_entry_double(significant: true, id: 888),
        build_entry_double(significant: false, id: 999),
      ]
      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {significant: 1})

      expect(search.results.count).to eq 1
    end

    it "applies basic sort order correctly" do
      entries = [
        build_entry_double(publication_date: '2000-01-01', id: 888),
        build_entry_double(publication_date: '2000-12-31', id: 999),
      ]
      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {}, order: 'newest')

      expect(search.results.es_ids).to eq([999,888])
    end

    it "handles array attributes" do
      entries = [
        entry,
        Factory(:entry, presidential_document_type_id: PresidentialDocumentType::DETERMINATION.id)
      ]
      entries.each{|entry| $entry_repository.save(entry) }

      $entry_repository.refresh_index! #TODO: Is this refresh needed?

      search = EsEntrySearch.new(
        conditions: {
          presidential_document_type: ['determination'],
        }
      )

      expect(search.results.count).to eq 1
    end

    it "handles Sphinx multi-value attribute queries" do
      agencies = (1..2).map{ Factory.create(:agency) } #Note that actual agencies must exist in order for the search to register the filter
      entries = [
        build_entry_double({agency_ids: agencies.first.id, id: 111 }),
        build_entry_double({agency_ids: agencies.last.id, id: 222 }),
        build_entry_double({agency_ids: [], id: 333 })
      ]
      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {agency_ids: agencies.map(&:id) })

      expect(search.results.count).to eq(2)
    end

    it "handles geolocation search" do
      entries = [
        build_entry_double({place_ids: [444,555], id: 999}),
      ]
      entries.each{|entry| $entry_repository.save(entry) }
      $entry_repository.refresh_index!

      search = EsEntrySearch.new(conditions: {place_ids: [444] })

      expect(search.results.es_ids).to eq([999])
    end

    context "handles date attribute queries" do
      [
        #gte, #lte, #is, #year, count
        ['2000-01-01', nil, nil, nil, 1],
        [nil, '1999-12-31', nil, nil, 1],
        [nil, nil, '2000-01-01', nil, 1],
        ['1970-01-01', '1999-12-31', nil, 2000, 1],
      ].each do |gte, lte, is, year, count|
        it "handles dates" do
          publication_date_conditions = {
            gte: gte,
            lte: lte,
            is: is,
            year: year,
          }.reject{|k, v| v.blank?}
          entries = [
            build_entry_double({publication_date: '1999-12-31', id: 888}),
            build_entry_double({publication_date: '2000-01-01', id: 999}),
          ]

          entries.each{|entry| $entry_repository.save(entry) }
          $entry_repository.refresh_index!

          search = EsEntrySearch.new(conditions: {publication_date: publication_date_conditions} )
          expect(search.results.count).to eq(count)
        end
      end
    end

  end

end