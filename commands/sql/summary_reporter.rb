require 'sql/summary_row_group'
require 'sql/summary_row'

module Sql
  class SummaryReporter
    attr_reader :query_group

    def initialize(query_group, defval, separator, formatter)
      @query_group = query_group
      @q = query_group.primary_query
      @lq = query_group[-1]
      @defval = defval
      @sep = separator
      @extra = @q.extra_fields
      @efields = @extra ? @extra.fields : nil
      @sorted_row_values = nil
    end

    def query
      @q
    end

    def ratio_query?
      @counts &&  @counts.size == 2
    end

    def summary
      @counts = []

      for q in @query_group do
        count = sql_count_rows_matching(q)
        @counts << count
        break if count == 0
      end

      @count = @counts[0]
      if @count == 0
        "No #{summary_entities} for #{@q.argstr}"
      else
        filter_count_summary_rows!
        ("#{summary_count} #{summary_entities} " +
          "for #{@q.argstr}: #{summary_details}")
      end
    end

    def report_summary
      puts(summary)
    end

    def count
      @counts[0]
    end

    def summary_count
      if @counts.size == 1
        @count == 1 ? "One" : "#{@count}"
      else
        @counts.reverse.join("/")
      end
    end

    def summary_entities
      type = @q.ctx.entity_name
      @count == 1 ? type : type + 's'
    end

    def filter_count_summary_rows!
      group_by = @q.summarise
      summary_field_count = group_by ? group_by.fields.size : 0

      rowmap = { }
      rows = []
      query_count = @query_group.size
      first = true
      for q in @query_group do
        sql_each_row_for_query(q.summary_query, *q.values) do |row|
          srow = nil
          if group_by then
            srow = SummaryRow.new(self,
              row[1 .. summary_field_count],
              row[0],
              @q.extra_fields,
              row[(summary_field_count + 1)..-1])
          else
            srow = SummaryRow.new(self, nil, nil, @q.extra_fields, row)
          end

          if query_count > 1
            filter_key = srow.key.to_s.downcase
            if first
              rowmap[filter_key] = srow
            else
              existing = rowmap[filter_key]
              existing.combine!(srow) if existing
            end
          else
            rows << srow
          end
        end
        first = false
      end

      raw_values = query_count > 1 ? rowmap.values : rows

      if query_count > 1
        raw_values.each do |rv|
          rv.extend!(query_count)
        end
      end

      filters = @query_group.filters
      if filters
        raw_values = raw_values.find_all do |row|
          filters.all? { |f| f.matches?(row) }
        end
      end

      if summary_field_count > 1
        raw_values = SummaryRowGroup.new(self).unify(raw_values)
      else
        raw_values = SummaryRowGroup.new(self).sort(raw_values)
      end

      @sorted_row_values = raw_values
      if filters
        @counts = count_filtered_values(@sorted_row_values)
      end
    end

    def summary_details
      @sorted_row_values.join(", ")
    end

    def count_filtered_values(sorted_summary_row_values)
      counts = [0, 0]
      for summary_row_value in sorted_summary_row_values
        if summary_row_value.counts
          row_count = summary_row_value.counts
          counts[0] += row_count[0]
          if row_count.size == 2
            counts[1] += row_count[1]
          end
        end
      end
      return counts[1] == 0 ? [counts[0]] : counts
    end
  end
end
