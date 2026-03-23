# frozen_string_literal: true
class BidirectionalLinksGenerator < Jekyll::Generator
  safe true
  priority :low

  def generate(site)
    graph_nodes = []
    graph_edges = []

    # Collect notes and pages
    all_notes = site.collections['notes']&.docs || []
    all_pages = site.pages.select { |p| p.data['title'] && p.data.fetch('output', true) != false }
    all_posts = site.posts.docs
    all_docs  = (all_notes + all_pages + all_posts).uniq

    all_docs = (all_notes + all_pages).uniq

    link_extension = site.config["use_html_extension"] ? '.html' : ''

    # --- 1) Convert [[Wiki Links]] in every doc to <a class='internal-link'> ---
    all_docs.each do |current_doc|
      all_docs.each do |target|
        # filename without extension (with flexible _ / - matching)
        filename_pattern = Regexp.escape(
          File.basename(target.basename, File.extname(target.basename))
        ).gsub('\_', '[ _]').gsub('\-', '[ -]').capitalize

        # title from front matter (if present)
        title_from_data = target.data['title'] ? Regexp.escape(target.data['title']) : nil

        new_href   = "#{site.baseurl}#{target.url}#{link_extension}"
        anchor_tag = "<a class='internal-link' href='#{new_href}'>\\1</a>"

        # [[Title|label]] (match by filename)
        current_doc.content.gsub!( /\[\[#{filename_pattern}\|(.+?)(?=\])\]\]/i, anchor_tag )
        # [[Title|label]] (match by front matter title)
        current_doc.content.gsub!( /\[\[#{title_from_data}\|(.+?)(?=\])\]\]/i, anchor_tag ) if title_from_data

        # [[Title]] (front matter)
        current_doc.content.gsub!( /\[\[(#{title_from_data})\]\]/i, anchor_tag ) if title_from_data
        # [[filename]] (basename)
        current_doc.content.gsub!( /\[\[(#{filename_pattern})\]\]/i, anchor_tag )
      end

      # Any remaining [[...]] are missing/hidden: mark invalid
      current_doc.content = current_doc.content.gsub(
        /\[\[([^\]]+)\]\]/i,
        <<~HTML.delete("\n")
          <span title='this note is still private.' class='invalid-link'>
            <span class='invalid-link-brackets'>[[</span>
            \\1
            <span class='invalid-link-brackets'>]]</span>
          </span>
        HTML
      )
    end

    # --- 2) Build nodes + edges across ALL docs (notes + pages) ---
    all_docs.each do |current|
      # Node kind
      kind =
        if all_notes.include?(current) then 'note'
        elsif all_posts.include?(current) then 'post'
        else 'page'
        end

      # Node
      graph_nodes << {
        id: note_id_from(current),
        path: "#{site.baseurl}#{current.url}#{link_extension}",
        label: current.data['title'],
        kind: kind,
      }
    end

    # Edges (find any doc that links to current via the rendered href)
    all_docs.each do |current|
      hrefs = [
        "#{site.baseurl}#{current.url}",
        "#{site.baseurl}#{current.url}#{link_extension}",
        current.url,
        "#{current.url}#{link_extension}"
      ].uniq

      linking_docs = all_docs.select do |d|
        html = d.content
        hrefs.any? { |h| html.include?(%Q{href="#{h}"}) || html.include?(%Q{href='#{h}'}) }
      end.reject { |d| d.equal?(current) }

      # Optional: keep backlinks list on notes
      current.data['backlinks'] = linking_docs if all_notes.include?(current)

      linking_docs.each do |d|
        graph_edges << { source: note_id_from(d), target: note_id_from(current) }
      end
    end

    File.write('_includes/notes_graph.json', JSON.dump({ edges: graph_edges, nodes: graph_nodes }))
  end

  def note_id_from(doc)
    doc.data['title'].to_s.bytes.join
  end
end