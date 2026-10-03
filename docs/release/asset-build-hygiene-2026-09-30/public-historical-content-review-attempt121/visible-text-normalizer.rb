require "json"
require "cgi"
require "digest"
build, baseline = ARGV
hashes = JSON.parse(File.read(baseline)).fetch("hashes")
rows=hashes.to_h do |route, expected|
  html=File.read(File.join(build, route.delete_prefix("/"), "index.html")).gsub(/<script\b.*?<\/script>/mi," ").gsub(/<style\b.*?<\/style>/mi," ")
  if html.include?('class="mobile-menu-actions"')
    html=html.sub(%r{<div class="header-actions">\s*<a[^>]*>Get the App</a>\s*</div>}, "")
  end
  text=CGI.unescapeHTML(html.gsub(/<[^>]+>/,"\n")).lines.map{|line|line.gsub(/\s+/," ").strip}.reject(&:empty?).join("\n").gsub(/© \d{4}/,"© YEAR")
  [route,{"text"=>text,"sha256"=>Digest::SHA256.hexdigest(text),"expected"=>expected}]
end
puts JSON.generate(rows)
