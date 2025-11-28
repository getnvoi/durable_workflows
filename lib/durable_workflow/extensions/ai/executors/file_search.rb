# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class FileSearch < Core::Executors::Base
          def call(state)
            query = resolve(state, config.query)
            files = config.files
            max_results = config.max_results

            results = search_files(query, files, max_results)

            state = store(state, config.output, results) if config.output
            continue(state, output: results)
          end

          private

            def search_files(query, files, max_results)
              # Placeholder - returns dummy results
              # In production, integrate with vector stores (OpenAI, Pinecone, etc.)
              dummy_results = generate_dummy_results(query, files, max_results)

              {
                query:,
                results: dummy_results,
                total: dummy_results.size,
                searched_files: files.size,
                max_results:
              }
            end

            def generate_dummy_results(query, files, max_results)
              return [] if files.empty?

              # Generate plausible dummy results based on query
              files.take(max_results).map.with_index do |file, idx|
                {
                  file: file,
                  score: (0.95 - idx * 0.1).round(2),
                  snippet: "...relevant content matching '#{query}' found in #{file}...",
                  line_number: rand(1..100)
                }
              end
            end
        end
      end
    end
  end
end
