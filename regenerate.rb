require 'net/http'
require 'json'
require 'nokogiri'
require 'color'

uri = URI('https://resultats.primaire2016.org/assets/data/france_departments.json')
raw_data = Net::HTTP.get(uri)

data = JSON.parse(raw_data, symbolize_names: true)

doc = Nokogiri::XML(open("base.svg"))

FILLON = "François Fillon"
JUPPE = "Alain Juppé"

deps = data[:departments].map do |key, value|
  fillon_data = value[:candidates].find { |cand| cand[:name] == FILLON }
  juppe_data = value[:candidates].find { |cand| cand[:name] == JUPPE }

  {
      number: key.to_s.downcase.rjust(2, '0'),
      name: value[:name],
      fillon_votes: fillon_data[:votes],
      fillon_percentage: fillon_data[:votes].to_f / value[:total] * 100.0,
      juppe_votes: juppe_data[:votes],
      juppe_percentage: juppe_data[:votes].to_f / value[:total] * 100.0
  }
end.to_a

FILLON_COLOR_LOW = Color::RGB.by_hex('#d1fbff').to_hsl
FILLON_COLOR_HIGH = Color::RGB.by_hex('#3aefff').to_hsl
JUPPE_COLOR_LOW = Color::RGB.by_hex('#ffeac6').to_hsl
JUPPE_COLOR_HIGH = Color::RGB.by_hex('#ffb942').to_hsl

GREY = Color::RGB.by_name('lightgrey')

MARGIN = 30.0

def interpolate_color_value(low_color, high_color, percentage)
  if high_color < low_color
    low_color + (high_color - low_color) * [1, (percentage - 50.0) / MARGIN].min
  else
    high_color + (low_color - high_color) * [1, (percentage - 50.0) / MARGIN].min
  end

end

def saturate_based_on_percentage(low_color, high_color, percentage)
  color = Color::HSL.new(0, 0, 0)
  color.h = interpolate_color_value(low_color.h, high_color.h, percentage)
  color.s = interpolate_color_value(low_color.s, high_color.s, percentage)
  color.l = interpolate_color_value(low_color.l, high_color.l, percentage)
  color.to_rgb
end

deps.each do |departement|
  group = doc.css(".departement#{departement[:number]}").first

  total = departement[:fillon_percentage] + departement[:juppe_percentage]

  if total == 0 || departement[:fillon_percentage] == 50 || departement[:fillon_percentage] == 0
    color = GREY
    winner = 'Inconnu'
    winner_percentage = 0
  else
    fillon_percentage = departement[:fillon_percentage] / total * 100.0
    juppe_percentage = departement[:juppe_percentage] / total * 100.0

    if fillon_percentage > 50
      color = saturate_based_on_percentage(FILLON_COLOR_LOW, FILLON_COLOR_HIGH, fillon_percentage)
    else
      color = saturate_based_on_percentage(JUPPE_COLOR_LOW, JUPPE_COLOR_HIGH, juppe_percentage)
    end

    if fillon_percentage == 50
      winner = 'Inconnu'
      winner_percentage = 50
    else
      winner = fillon_percentage > 50 ? FILLON : JUPPE
      winner_percentage = fillon_percentage > 50 ? fillon_percentage : juppe_percentage
    end
  end

  if group
    group['title'] = "#{departement[:name]} (#{winner} avec #{winner_percentage.round(2)} %)"
    group['style'] = "fill: #{color.css_hsl}"
  end
end

legend_juppe = doc.css('#legend-alainjuppe').first
legend_juppe['style'] = "#{legend_juppe['style']}; fill: #{JUPPE_COLOR_HIGH.css_hsl}"

legend_fillon = doc.css('#legend-francoisfillon').first
legend_fillon['style'] = "#{legend_fillon['style']}; fill: #{FILLON_COLOR_HIGH.css_hsl}"

data_hour = Time.at(data[:timestamp] / 1000).strftime('%H:%M')

hour_label = doc.css('#heure').first
hour_label.content = data_hour

france = data[:departments]['0'.to_sym]
fillon_france_data = france[:candidates].find { |cand| cand[:name] == FILLON }
juppe_france_data = france[:candidates].find { |cand| cand[:name] == JUPPE }

fillon_france_percentage = fillon_france_data[:porcentage]
juppe_france_percentage = juppe_france_data[:porcentage]

bar_juppe = doc.css('#bar-juppe').first
bar_juppe['style'] =  "fill: #{JUPPE_COLOR_HIGH.css_hsl}"
bar_juppe['width'] = bar_juppe['width'].to_f * juppe_france_percentage / 100.0

bar_fillon = doc.css('#bar-fillon').first
bar_fillon['style'] =  "fill: #{FILLON_COLOR_HIGH.css_hsl}"
new_fillon_width = bar_fillon['width'].to_f * fillon_france_percentage / 100.0
bar_fillon['x'] = bar_fillon['x'].to_i + bar_fillon['width'].to_i - new_fillon_width
bar_fillon['width'] = new_fillon_width

france_fillon = doc.css('#france-fillon').first
france_fillon.content = "#{fillon_france_percentage.round(2)} %"

france_juppe = doc.css('#france-juppe').first
france_juppe.content = "#{juppe_france_percentage.round(2)} %"

legend_bureaux = doc.css('#legend-resultats').first
legend_bureaux.content = "sur #{france[:"BV-counted"]} / #{france[:"BV-total"]} bureaux"

bar_bv = doc.css('#bar-bv').first
bar_bv['width'] = ((france[:"BV-counted"].to_f / france[:"BV-total"].to_f) * 200.0).to_i
bar_bv['style'] = 'fill: #999999'

File.open('output.svg', 'w') do |f|
  f.write(doc.to_html)
end

system("inkscape -z --export-png=public/output-#{data_hour.gsub(':', '-')}.png output.svg")