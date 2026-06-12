# Zeller's ddmin (delta debugging) over an array of items. Yields
# candidate subsets to the block; the block returns true if the
# candidate still "fails interestingly" (the caller decides what that
# means - for the harness it's "fails with the same signature").
# Returns a 1-minimal failing subset.
module Harness
  module DDMin
    def self.minimize(items, &fails)
      cur = items
      n = 2
      while cur.length >= 2
        chunk_len = (cur.length / n.to_f).ceil
        chunks = cur.each_slice(chunk_len).to_a
        reduced = false

        chunks.each do |chunk|
          next if chunk.length == cur.length
          if fails.call(chunk)
            cur = chunk
            n = 2
            reduced = true
            break
          end
        end

        if !reduced && n > 2
          chunks.each_with_index do |_, i|
            comp = (chunks[0...i] + chunks[i + 1..]).flatten(1)
            next if comp.empty? || comp.length == cur.length
            if fails.call(comp)
              cur = comp
              n = [n - 1, 2].max
              reduced = true
              break
            end
          end
        end

        if !reduced
          break if n >= cur.length
          n = [n * 2, cur.length].min
        end
      end
      cur
    end
  end
end
