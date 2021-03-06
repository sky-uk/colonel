When(/^I promote "(.*?)" to "(.*?)"$/) do |from, to|
  author = {name: 'Test', email: 'test@example.com'}
  @new_revision = @document.promote!(from, to, author, 'Promoted')
end

Then(/^the "(.*?)" revision should have content:$/) do |state, table|
  state_rev = @document.revisions[state]

  expect(state_rev).to be_a(Revision)

  table.hashes.first.each do |key, value|
    expect(state_rev.content.get(key)).to eq(value)
  end
end

When(/^I save the changes to "(.*?)"$/) do |state|
  @document.save_in!(state, {name: 'Test', email: 'test@example.com'})
end

Given(/^an document with the following history:$/) do |table|
  @document = Document.new({foo: 'bar'})
  author = {name: 'Test', email: 'test@example.com'}

  table.hashes.each do |revision|
    case revision[:change]
    when 'save'
      @document.save!(author, revision[:message])
    when 'publish'
      @document.promote!('master', 'published', author, revision[:message])
    when 'retire'
      @document.promote!('published', 'retired', author, revision[:message])
    when 'hotfix'
      @document.save_in!('published', author, revision[:message])
    end
  end
end

When(/^I list the "(.*?)" history$/) do |state|
  @history = @document.history(state)
end

Then(/^I should get the following revisions:$/) do |table|
  table.hashes.each do |revision|
    rev = @history.next

    expect(rev.type).to eq(revision[:type].to_sym)
    expect(rev.state).to eq(revision[:state])
    expect(rev.message).to eq(revision[:message])
  end

  another = nil
  expect {
    another = @history.next
  }.to raise_error, "Expected iteration to end, got #{another.inspect}"
end

Then(/^I should get the following results of checking promotion:$/) do |table|
  table.hashes.each do |revision|
    rev = @history.next

    published = case revision[:published]
      when 'true'
        true
      when 'false'
        false
    end

    retired = case revision[:retired]
      when 'true'
        true
      when 'false'
        false
    end

    expect(rev.message).to eq(revision[:message])
    expect(rev.has_been_promoted?('published')).to eq(published)
    expect(rev.has_been_promoted?('retired')).to eq(retired)
  end

  expect {
    @history.next
  }.to raise_error
end
