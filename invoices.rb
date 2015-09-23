require 'harvested'
require 'highline/import'
require 'json'
require 'Date'

credentials = {}

begin
  credentials_file = IO.read('.credentials')
  credentials = JSON.parse(credentials_file)
rescue JSON::ParserError => err
  puts err
  puts "Didn't read email and password from .credentials"
end

puts

csv_filename = ARGV.length > 0 ? ARGV[0] : ask("Enter path to .csv file with |Sprint number|Sprint start date|Sprint end date|Sprint comments|:") { |q| q.echo = true }
last_sprint_end = nil
# Make sure the CSV file is valid
CSV.foreach(csv_filename, { :col_sep => "\t" }) do |row|
  sprint_number = row[0]
  sprint_start = Date.strptime(row[1], "%m/%d/%Y")
  sprint_end = Date.strptime(row[2], "%m/%d/%Y")

  if last_sprint_end
    if last_sprint_end + 1 != sprint_start
      puts "ERROR sprint #{sprint_number} doesn't start the day after the previous sprint"
      exit
    end
  end
  last_sprint_end = sprint_end
end

email = credentials['email'] || ask("Enter your email: ") { |q| q.echo = true }
password = credentials['password'] || ask("Enter your password: ") { |q| q.echo = "*" }
subdomain = 'fretboard'

harvest = Harvest.hardy_client(subdomain: subdomain, username: email, password: password)

clients = harvest.clients.all
client_id = choose do |menu|
  menu.prompt = "Choose client: "

  clients.each {|client| menu.choice(client.name) { client.id } }
end

puts

projects = harvest.projects.all
project = choose do |menu|
  menu.prompt = "Choose project: "

  projects.each do |project|
    if project.client_id == client_id
      menu.choice(project.name) { project }
    end
  end
end
project_id = project.id

puts

# Generate invoices
CSV.foreach(csv_filename, { :col_sep => "\t" }) do |row|
  sprint_number = row[0]
  sprint_start = Date.strptime(row[1], "%m/%d/%Y")
  sprint_end = Date.strptime(row[2], "%m/%d/%Y")
  sprint_notes = row[3]

  invoice = Harvest::Invoice.new(
    client_id: client_id,
    subject: "#{project.name} invoice for #{sprint_start} - #{sprint_end}",
    notes: sprint_notes,
    kind: :project,
    projects_to_invoice: project_id,
    import_hours: :yes,
    import_expenses: :yes,
    period_start: sprint_start.strftime('%d-%m-%Y'),
    period_end: sprint_end.strftime('%d-%m-%Y'),
    expense_period_start: sprint_start.strftime('%d-%m-%Y'),
    expense_period_end: sprint_end.strftime('%d-%m-%Y')
  )
  invoice = harvest.invoices.create(invoice)

  puts "Generated invoice for sprint #{sprint_number}"
end

puts "All done! Go to https://fretboard.harvestapp.com/invoices, save them as PDFs, email, then mark as sent."
