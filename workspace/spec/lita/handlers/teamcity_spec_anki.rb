require 'spec_helper'

describe Lita::Handlers::Teamcity, lita_handler: true do
  before do
    registry.config.handlers.teamcity.site             = 'https://site.teamcity.com'
    registry.config.handlers.teamcity.username         = 'username'
    registry.config.handlers.teamcity.password         = 'password'
    registry.config.handlers.teamcity.git_uri          = 'git@github.com:git_uri'
    registry.config.handlers.teamcity.python_script    = 'python python_script.py'
  end

  describe '#id_build' do
    build_type         = "XXX_Master_Build"
    build_number       = "333"
    success_build_json = '{"count":2,"build":[{"id":11111,"buildTypeId":"#{build_type}","number":"111"},
                                              {"id":22222,"buildTypeId":"#{build_type}","number":"222"}]}'
    build_by_id_json   = '{"count":1,"build":[{"id":33333,"buildTypeId":"#{build_type}","number":"333"}]}'

    before do
      stub_request(:get, /status:SUCCESS,state:finished/).to_return(:status => 200, :body => success_build_json)
      stub_request(:get, /number:/).to_return(:status => 200, :body => build_by_id_json)
    end

    it 'Return latest success build if no build_number was provided' do
      id, number = subject.id_build(build_type)
      expect([id, number]).to eq([11111, "111"])
    end

    it 'Return build with provided build_number if it is provided' do
      id, number = subject.id_build(build_type, build_number)
      expect([id, number]).to eq([33333, "333"])
    end

    it 'Return empty build id and inputted build number if any exceptions was throw out.' do
      stub_request(:get, /status:SUCCESS,state:finished/).to_raise(StandardError)
      id, number = subject.id_build(build_type)
      expect([id, number]).to eq(["", ""])
    end

    it 'Return empty build id and inputted build number if no build was found.' do
      success_build_json = '{"count":0,"build":[]}'
      stub_request(:get, /status:SUCCESS,state:finished/).to_return(:status => 200, :body => success_build_json)

      id, number = subject.id_build(build_type, build_number)
      expect([id, number]).to eq(["", build_number])
    end
  end
  
  describe '#remaining_time' do
    build_id = "111111"

    it 'return empty string if build is not in running state' do
      running_build_json = '{"id":111111}'
      stub_request(:get, /id:/).to_return(:status => 200, :body => running_build_json)
      return_time, is_overtime = subject.remaining_time(build_id)
      expect([return_time, is_overtime]).to eq(["", false])
    end

    it 'time left is formatted correctly when elapsedSeconds > estimatedTotalSeconds' do
      running_build_json = '{"id":111111,"running-info":
                            {"percentageComplete":80,"elapsedSeconds":5000,"estimatedTotalSeconds":4000}}'
      stub_request(:get, /id:/).to_return(:status => 200, :body => running_build_json)
      return_time, is_overtime = subject.remaining_time(build_id)
      expect([return_time, is_overtime]).to eq(["16m:40s", true])
    end

    it 'time left is formatted correctly when elapsedSeconds < estimatedTotalSeconds' do
      running_build_json = '{"id":111111,"running-info":
                            {"percentageComplete":80,"elapsedSeconds":4000,"estimatedTotalSeconds":5000}}'
      stub_request(:get, /id:/).to_return(:status => 200, :body => running_build_json)
      return_time, is_overtime = subject.remaining_time(build_id)
      expect([return_time, is_overtime]).to eq(["16m:40s", false])
    end
  end
  
  describe '#format_result_running_build' do
    build_json_str_without_branch = '{"id":11111,"buildTypeId":"XXX_Master_Build",
                                      "number":"111","percentageComplete":80}'
    build_json_str                = '{"id":11111,"buildTypeId":"XXX_Master_Build",
                                      "number":"111","branchName":"BI-123-XYZ","percentageComplete":80}'
    running_build_json_overtime   = '{"id":111111,"running-info":
                                     {"elapsedSeconds":5000,"estimatedTotalSeconds":4000}}'
    running_build_json            = '{"id":111111,"running-info":
                                     {"elapsedSeconds":4000,"estimatedTotalSeconds":5000}}'

    before do
      stub_request(:get, /id:/).to_return(:status => 200, :body => running_build_json)
    end

    it 'result not contains branch path if branch is empty' do
      output_string = subject.format_result_running_build(JSON.parse(build_json_str_without_branch))
      expect(output_string).not_to end_with "- "
    end

    it 'result contains branch text if branch is not empty' do
      output_string = subject.format_result_running_build(JSON.parse(build_json_str))
      expect(output_string).to end_with "- BI-123-XYZ"
    end

    it 'result contains overtime part if build is overtime' do
      stub_request(:get, /id:/).to_return(:status => 200, :body => running_build_json_overtime)
      output_string = subject.format_result_running_build(JSON.parse(build_json_str))
      expect(output_string).to include("- Over time:")
    end

    it 'result contains time left part if build is not overtime' do
      output_string = subject.format_result_running_build(JSON.parse(build_json_str))
      expect(output_string).to include("- Time left:")
    end
  end
  
  describe '#format_result_queue_build' do
    build_json_str_without_branch = '{"id":11111,"buildTypeId":"XXX_Master_Build",
                                      "number":"111","percentageComplete":80}'
    build_json_str                = '{"id":11111,"buildTypeId":"XXX_Master_Build",
                                      "number":"111","branchName":"BI-123-XYZ","percentageComplete":80}'

    it 'result not contains branch path if branch is empty' do
      output_string = subject.format_result_queue_build(JSON.parse(build_json_str_without_branch))
      expect(output_string).not_to end_with "- "
    end

    it 'result contains branch text if branch is not empty' do
      output_string = subject.format_result_queue_build(JSON.parse(build_json_str))
      expect(output_string).to end_with "- BI-123-XYZ"
    end
  end

  describe '#fetch_build_types' do
    build_type_json_str = '{"buildType":[{"id":"Wildcard_A","projectName":"Wildcard :: A"},
                                         {"id":"B_Wildcard","projectName":"Wildcard :: B"},
                                         {"id":"C_Wildcard_C","projectName":"Wildcard :: C"},
                                         {"id":"NoneProject","projectName":"None :: None"}]}'

    before do
      stub_request(:get, /buildTypes/).to_return(:status => 200, :body => build_type_json_str)
    end

    it 'response_str contains all builds if build_id_wildcard is nil' do
      output_string = subject.fetch_build_types(nil)
      expect(output_string).to include("Wildcard_A", "Wildcard :: A", "B_Wildcard", "Wildcard :: B", 
                                       "C_Wildcard_C", "Wildcard :: C", "NoneProject", "None :: None")
    end

    it 'response_str contains all builds that build_id contains build_id_wildcard' do
      output_string = subject.fetch_build_types("Wildcard")
      expect(output_string).to include("Wildcard_A", "Wildcard :: A", "B_Wildcard", "Wildcard :: B", 
                                       "C_Wildcard_C", "Wildcard :: C")
    end

    it 'response_str is empty if no build_id contains build_id_wildcard' do
      output_string = subject.fetch_build_types("Invalid")
      expect(output_string).to eq("")
    end
  end

  describe '#artifacts_by_build_id' do
    build_type = "XXX_Master_Build"
    build_id   = "11111"

    it 'result eq.to empty if data[count] = 0' do
      artifact_json = '{"count":0,"file":[]}'
      stub_request(:get, /artifacts/).to_return(:status => 200, :body => artifact_json)
      output_string = subject.artifacts_by_build_id(build_type, build_id)
      expect(output_string).to eq("")
    end

    it 'result eq.to empty if data[count] > 0 and data[file] is empty' do
      artifact_json = '{"count":1,"file":[]}'
      stub_request(:get, /artifacts/).to_return(:status => 200, :body => artifact_json)
      output_string = subject.artifacts_by_build_id(build_type, build_id)
      expect(output_string).to eq("")
    end

    it 'result not contains empty artifact name if file[name] = ""' do
      artifact_json = '{"count":1,"file":[{"name":"","size":63}]}'
      stub_request(:get, /artifacts/).to_return(:status => 200, :body => artifact_json)
      output_string = subject.artifacts_by_build_id(build_type, build_id)
      expect(output_string).not_to include("|>")
    end

    it 'result contains all artifacts url and text' do
      artifact_name_1 = "filename1"
      artifact_name_2 = "filename2"
      artifact_url_1  = "#{registry.config.handlers.teamcity.site}/repository/download/"\
                        "#{build_type}/#{build_id}:id/#{artifact_name_1}"
      artifact_url_2  = "#{registry.config.handlers.teamcity.site}/repository/download/"\
                        "#{build_type}/#{build_id}:id/#{artifact_name_2}"
      expected_output = "\n<#{artifact_url_1}|#{artifact_name_1}>\n<#{artifact_url_2}|#{artifact_name_2}>"
      artifact_json   = '{"count":1,"file":[{"name":"filename1","size":63},{"name":"filename2","size":63}]}'
      stub_request(:get, /artifacts/).to_return(:status => 200, :body => artifact_json)
      output_string   = subject.artifacts_by_build_id(build_type, build_id)
      expect(output_string).to eq(expected_output)
    end
  end
  
  describe '#format_time' do

    it 'format_time with time > 3600' do
      output_string = subject.format_time(3700)
      expect(output_string).to eq("%Hh:%Mm:%Ss")
    end

    it 'format_time with time > 60 and <= 3600' do
      output_string = subject.format_time(3600)
      expect(output_string).to eq("%Mm:%Ss")
    end

    it 'format_time with time <= 60' do
      output_string = subject.format_time(60)
      expect(output_string).to eq("%Ss")
    end
  end

  describe '#queue' do
    queue_build_json_str = '{ "count": 2,
                              "build": [{"buildTypeId": "XXX_Master_Build",
                                         "branchName": "BI-123-XYZ",
                                         "id": "1111"},
                                        {"buildTypeId": "YYY_Release_Build",
                                         "branchName": "BI-124-XYZ",
                                         "id": "2222"}]}'
    before do
      stub_request(:get, /buildQueue/).to_return(:status => 200, :body => queue_build_json_str)
    end

    it 'replies all found running builds if wildcard = False' do
      expected_output = "Here are the builds I found:\n"\
                        "\n<#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=1111"\
                        "|XXX_Master_Build> - BI-123-XYZ"\
                        "\n<#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=2222"\
                        "|YYY_Release_Build> - BI-124-XYZ"
      send_command('queue')
      expect(replies.last).to eq(expected_output)
    end

    it 'replies the correct running builds if wildcard = True' do
      expected_output = "Here are the builds I found:\n"\
                        "\n<#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=1111"\
                        "|XXX_Master_Build> - BI-123-XYZ"
      send_command('queue Master*')
      expect(replies.last).to eq(expected_output)
    end
    
    it 'replies "runningbuildtypes.empty" when no have queue was found if call "Queue"' do
      queue_build_json_str = '{ "count": 0,
                                "build": [{"buildTypeId": "XXX_Master_Build",
                                           "branchName": "BI-123-XYZ",
                                           "id": "1111"},
                                          {"buildTypeId": "YYY_Release_Build",
                                           "branchName": "BI-124-XYZ",
                                           "id": "2222"}]}'
      stub_request(:get, /buildQueue/).to_return(:status => 200, :body => queue_build_json_str)
      expected_output = "Cannot find any builds to list!"
      send_command('queue')
      expect(replies.last).to eq(expected_output)
    end

    it 'replies "error.request" if connection to Teamcity is error' do
      stub_request(:get, /buildQueue/).to_return(:status => 400, :body => [])
      expected_output = "Error fetching TeamCity build types"
      send_command("queue")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#fetch_queue_build' do
    queue_build_json_str = '{"count": 2,
                             "build": [{"buildTypeId": "XXX_Master_Build",
                                        "branchName": "BI-123-XYZ",
                                        "id": "1111"},
                                       {"buildTypeId": "YYY_Release_Build",
                                        "branchName": "BI-124-XYZ",
                                        "id": "2222"}]}'
    before do
      stub_request(:get, /buildQueue/).to_return(:status => 200, :body => queue_build_json_str)
    end

    it 'returns all correct queue builds if "build_id_wildcard" is found' do
      build_id_wildcard = "XXX_Master_Build"
      expected_output   = "\n<#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=1111"\
                          "|#{build_id_wildcard}> - BI-123-XYZ"
      output_string     = subject.fetch_queue_build(build_id_wildcard)
      expect(output_string).to eq(expected_output)
    end

    it 'returns all found queue builds if "build_id_wildcard == nil"' do
      build_id_wildcard = nil
      expected_output   = "\n<#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=1111"\
                          "|XXX_Master_Build> - BI-123-XYZ"\
                          "\n<#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=2222"\
                          "|YYY_Release_Build> - BI-124-XYZ"
      output_string     = subject.fetch_queue_build(build_id_wildcard)
      expect(output_string).to eq(expected_output)
    end

    it "returns empty if 'build_id_wildcard' isn't found"  do
      build_id_wildcard = "invalid"
      expected_output   = ""
      output_string     = subject.fetch_queue_build(build_id_wildcard)
      expect(output_string).to eq(expected_output)
    end

    it 'returns empty if "count == 0" or "build" is empty' do
      build_id_wildcard          = "XXX_Master_Build"
      empty_queue_build_json_str = '{"count": 0,
                                     "build": []}'
      stub_request(:get, /buildQueue/).to_return(:status => 200, :body => empty_queue_build_json_str)
      expected_output = ""
      output_string   = subject.fetch_queue_build(build_id_wildcard)
      expect(output_string).to eq(expected_output)
    end
  end

  describe '#fetch_running_build' do
    running_build_json_str = '{"count": 2,
                               "build": [{"id": 123456,
                                          "buildTypeId": "Build_Type_Id_1",
                                          "number": "123",
                                          "branchName": "Test_Branch_1",
                                          "percentageComplete": 50},
                                         {"id": 121212,
                                          "buildTypeId": "Build_Type_Id_2",
                                          "number": "234",
                                          "branchName": "Test_Branch_2",
                                          "percentageComplete": 50}]}'
    builds_json_str        = '{"running-info": {"estimatedTotalSeconds": "10",
                                                "elapsedSeconds": "1"}}'

    before do
      stub_request(:get, /running:true/).to_return(:status => 200, :body => running_build_json_str)
      stub_request(:get, /id:/).to_return(:status => 200, :body => builds_json_str)
    end

    it 'returns correct running build if build_id_wildcard is found' do    
      expected_string = "\n<#{registry.config.handlers.teamcity.site}/viewLog.html?buildId=123456&buildTypeId=" \
                        "Build_Type_Id_1|Build_Type_Id_1> (123) - `50%` complete - Time left: `09s` - Test_Branch_1"
      output_string   = subject.fetch_running_build("Build_Type_Id_1")
      expect(output_string).to eq(expected_string)
    end

    it 'returns all running build if build_id_wildcard is nil' do    
      expected_string = "\n<#{registry.config.handlers.teamcity.site}/viewLog.html?buildId=123456&buildTypeId=" \
                        "Build_Type_Id_1|Build_Type_Id_1> (123) - `50%` complete - Time left: `09s` - Test_Branch_1" \
                        "\n<#{registry.config.handlers.teamcity.site}/viewLog.html?buildId=121212&buildTypeId=" \
                        "Build_Type_Id_2|Build_Type_Id_2> (234) - `50%` complete - Time left: `09s` - Test_Branch_2"
      output_string   = subject.fetch_running_build(nil)
      expect(output_string).to eq(expected_string)
    end

    it 'returns empty if count = 0 or build is empty' do
      empty_running_build_json_str = '{"count": 0,
                                       "build": []}'
      stub_request(:get, /running:true/).to_return(:status => 200, :body => empty_running_build_json_str)
      expected_string = ""
      output_string   = subject.fetch_running_build(nil)
      expect(output_string).to eq(expected_string)
    end

    it 'returns empty if build_id_wildcard is not found' do
      expected_string = ""
      output_string   = subject.fetch_running_build("Test")
      expect(output_string).to eq(expected_string)
    end
  end

  describe '#list' do
    build_type_json_str = '{"buildType":[{"id":"Wildcard_A","projectName":"Wildcard :: A"},
                                         {"id":"B_Wildcard","projectName":"Wildcard :: B"},
                                         {"id":"Test_ABC","projectName":"Test :: ABC"}]}'
    before do
      stub_request(:get, /buildTypes/).to_return(:status => 200, :body => build_type_json_str)
    end

    it 'replies the correct builds if wildcard exists' do
      wildcard        = "Wildcard"
      expected_output = "Here are the builds I found:\n\n" \
                        "Wildcard :: A :: id=`Wildcard_A`\n" \
                        "Wildcard :: B :: id=`B_Wildcard` \n\n" \
                        "Use a build `id` from the list to trigger a build. *@buildbot build `id`*"
      send_command("list #{wildcard}*")
      expect(replies.last).to eq(expected_output)
    end

    it 'replies all builds if wildcard is empty' do
      expected_output = "Here are the builds I found:\n\n" \
                        "Wildcard :: A :: id=`Wildcard_A`\n" \
                        "Wildcard :: B :: id=`B_Wildcard`\n" \
                        "Test :: ABC :: id=`Test_ABC` \n\n" \
                        "Use a build `id` from the list to trigger a build. *@buildbot build `id`*"
      send_command("list")
      expect(replies.last).to eq(expected_output)
    end

    it 'replies buildtypes.empty if wildcard is invalid' do
      wildcard        = "Invalid_Wildcard"
      expected_output = "Cannot find any builds to list!"
      send_command("list #{wildcard}*")
      expect(replies.last).to eq(expected_output)
    end

    it 'replies error.request if no connection to Teamcity' do
      expected_output = "Error fetching TeamCity build types"
      stub_request(:get, /buildTypes/).to_raise(StandardError.new("connection error"))
      send_command("list")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#buildpr' do
    pr_number = "pr516"
    build_id  = "XXX_build"

    it 'result contains the correct builds url when triggering successfully' do
      build_url       = "#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=111111}"
      expected_output = "Build has been triggered: #{build_url}"
      body_str_xml    = "<build webUrl='#{build_url}'></build>"
      stub_request(:post, /buildQueue/).to_return(:status => 200, :body => body_str_xml)
      send_command("build #{pr_number} for #{build_id}")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#build' do
    build_id = "XXX_build"

    it 'result contains the correct builds url when triggering successfully' do
      build_url       = "#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=111111}"
      expected_output = "Build has been triggered: #{build_url}"
      body_str_xml    = "<build webUrl='#{build_url}'></build>"
      stub_request(:post, /buildQueue/).to_return(:status => 200, :body => body_str_xml)
      send_command("build #{build_id}")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#build_revision' do
    build_id = 'XXX_build'
    revision = '111'

    it 'result contains the correct url if triggering a build successfully' do
      expected_url    = "#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=111111"
      expected_output = "Build has been triggered: #{expected_url}"
      xml_body_str    = "<build webUrl='#{expected_url}'/>"
      stub_request(:post, /buildQueue/).to_return(:status => 200, :body => xml_body_str)
      send_command("build r#{revision} for #{build_id}")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#build_branch' do
    build_id = 'XXX_build'
    branch   = 'branch'
     it 'result contains the correct url if triggering a build successfully' do
      expected_url    = "#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=111111"
      expected_output = "Build has been triggered: #{expected_url}"
      xml_body_str    = "<build webUrl='#{expected_url}'/>"
      stub_request(:post, /buildQueue/).to_return(:status => 200, :body => xml_body_str)
      send_command("build #{build_id} #{branch}")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#build_branch_revision' do
    build_id = 'XXX_build'
    branch   = 'branch'
    revision = '111'

    it 'result contains the correct url if triggering a build successfully' do
      expected_url    = "#{registry.config.handlers.teamcity.site}/viewQueued.html?itemId=111111"
      expected_output = "Build has been triggered: #{expected_url}"
      xml_body_str    = "<build webUrl='#{expected_url}'/>"
      stub_request(:post, /buildQueue/).to_return(:status => 200, :body => xml_body_str)
      send_command("build r#{revision} for #{build_id} #{branch}")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#artifacts' do
    valid_build_name              = "XXX_Master_Build"
    invalid_build_name            = "invalid_Master_Build"
    valid_build_number            = "12345"
    real_build_number             = "123"
    artifacts_result_with_data    = "<url_1|artifact_1>\n<url_2|artifact_2>"
    artifacts_result_without_data = ""

    before do
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:id_build).\
                            and_return([valid_build_number, real_build_number])
    end

    it 'result artifacts.error returns if the returned build_id is empty' do
      expected_output = "Cannot find build #{invalid_build_name} ()!"
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:id_build).and_return(["", ""])
      send_command("artifacts #{invalid_build_name}")
      expect(replies.last).to eq(expected_output)
    end

    it 'No artifact was found if have_build_number = false and detail is empty' do
      expected_output = "No artifact was found in the given build number ()!"
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:artifacts_by_build_id).\
                            and_return(artifacts_result_without_data)
      send_command("artifacts #{valid_build_name}")
      expect(replies.last).to eq(expected_output)
    end

    it 'No artifact was found if have_build_number = true and detail is empty' do
      expected_output = "No artifact was found in the given build number (#{valid_build_number})!"
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:artifacts_by_build_id).\
                            and_return(artifacts_result_without_data)
      send_command("artifacts #{valid_build_name} #{valid_build_number}")
      expect(replies.last).to eq(expected_output)
    end

    it 'result returns correctly if have_build_number = false and detail is not empty' do
      expected_output = "Here are the artifacts of <#{registry.config.handlers.teamcity.site}/"\
                        "viewLog.html?buildId=#{valid_build_number}&buildTypeId="\
                        "#{valid_build_name}&tab=artifacts|#{valid_build_name} "\
                        "(#{real_build_number})>:\n#{artifacts_result_with_data}"
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:artifacts_by_build_id).\
                            and_return(artifacts_result_with_data)
      send_command("artifacts #{valid_build_name}")
      expect(replies.last).to eq(expected_output)
    end

    it 'result returns correctly if have_build_number = true and detail is not empty' do
      expected_output = "Here are the artifacts of <#{registry.config.handlers.teamcity.site}/"\
                        "viewLog.html?buildId=#{valid_build_number}&buildTypeId="\
                        "#{valid_build_name}&tab=artifacts|#{valid_build_name} "\
                        "(#{real_build_number})>:\n#{artifacts_result_with_data}"
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:artifacts_by_build_id).\
                            and_return(artifacts_result_with_data)
      send_command("artifacts #{valid_build_name} #{valid_build_number}")
      expect(replies.last).to eq(expected_output)
    end
  end

  describe '#list_cps_to_commit' do
    repo_name = "build-tools"
    repos_dir = File.join(Dir.home, 'repos')
    repo_uri  = "git@github.com:git_uri/#{repo_name}.git"

    before do
      allow(File).to receive(:exists?).with(repos_dir).and_return(true)
    end

    it "returns correct commit cherry picked when existing repo" do
      expected_output = "Commit git fetch name"
      allow(File).to receive(:exists?).with("#{repos_dir}/#{repo_name}").and_return(true)
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:`)
                            .with("cd #{repos_dir}/#{repo_name}/ && git fetch -p")
                            .and_return(true)
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:`)
                            .with("cd #{repos_dir}/#{repo_name}/ && #{registry.config.handlers.teamcity.python_script}")
                            .and_return(expected_output)
      send_command("cp_commits #{repo_name}")
      expect(replies.first).to eq("Fetching, please wait...")
      expect(replies.last).to eq("*Commits to be cherry picked:* ```#{expected_output}```")
    end

    it "returns correct commit cherry picked when non-existing repo" do
      expected_output = "Commit git clone name"
      allow(File).to receive(:exists?).with("#{repos_dir}/#{repo_name}").and_return(false)
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:`)
                            .with("cd #{repos_dir}/ && git clone #{repo_uri} #{repo_name}")
                            .and_return(true)
      allow_any_instance_of(Lita::Handlers::Teamcity).to receive(:`)
                            .with("cd #{repos_dir}/#{repo_name}/ && #{registry.config.handlers.teamcity.python_script}")
                            .and_return(expected_output)
      send_command("cp_commits #{repo_name}")
      expect(replies.first).to eq("I need to clone this repo, please wait...")
      expect(replies.last).to eq("*Commits to be cherry picked:* ```#{expected_output}```")
    end
  end
    
  describe '#running' do
    running_build_json_str = '{"count": 2,
                               "build": [{"buildTypeId": "ABC_Build",
                                          "branchName": "BI-123-XYZ",
                                          "id": "4307",
                                          "number":"1",
                                          "percentageComplete": "1"},
                                         {"buildTypeId": "XYZ_Build",
                                          "branchName": "BI-124-XYZ",
                                          "id": "4308",
                                          "number": "2",
                                          "percentageComplete": "2"}]}'
    builds_json_str        = '{"running-info": {"estimatedTotalSeconds": "10",
                                                "elapsedSeconds": "1"}}'
    time_diff              = "09s"

    before do
      stub_request(:get, /running:true/).to_return(:status => 200, :body => running_build_json_str)
      stub_request(:get, /id:/).to_return(:status => 200, :body => builds_json_str)
    end

    it 'replies all found running builds if wildcard = False' do
      expected_output = "Here are the builds I found:\n\n<#{registry.config.handlers.teamcity.site}"\
                        "/viewLog.html?buildId=4307"\
                        "&buildTypeId=ABC_Build|ABC_Build> (1) - "\
                        "`1\%` complete - Time left: `#{time_diff}` - BI-123-XYZ"\
                        "\n<#{registry.config.handlers.teamcity.site}/viewLog.html?buildId=4308"\
                        "&buildTypeId=XYZ_Build|XYZ_Build> (2) - "\
                        "`2\%` complete - Time left: `#{time_diff}` - BI-124-XYZ"
      send_command("running")
      expect(replies.last).to eq(expected_output)
    end

    it 'replies the correct running builds if wildcard = True' do
      build_id               = "ABC"
      expected_build_type_id = "ABC_Build"
      expected_output        = "Here are the builds I found:\n\n<#{registry.config.handlers.teamcity.site}"\
                               "/viewLog.html?buildId=4307"\
                               "&buildTypeId=#{expected_build_type_id}|#{expected_build_type_id}> (1) - "\
                               "`1\%` complete - Time left: `#{time_diff}` - BI-123-XYZ"
      send_command("running #{build_id}*")
      expect(replies.last).to eq(expected_output)
    end

    it 'replies "error.request" if connection to Teamcity is error' do
      build_id        = "ABC"
      expected_output = "Error fetching TeamCity build types"
      stub_request(:get, /running:true/).to_raise(StandardError.new("connection error"))
      send_command("running #{build_id}*")
      expect(replies.last).to eq(expected_output)
    end

    it 'replies "runningbuildtypes.empty" if build_id is invalid' do
      build_id        = "invalid"
      expected_output = "Cannot find any builds to list!"
      send_command("running #{build_id}*")
      expect(replies.last).to eq(expected_output)
    end
  end

end
