require "../spec_helper"

private WINDOW = %({"id": 4211, "app": "Ghostty", "bundle_id": "com.mitchellh.ghostty", "pid": 812, ) +
                 %("title": "kx — zsh", "frame": {"x": 0, "y": 38, "w": 945, "h": 1080}, ) +
                 %("screen": 1, "focused": true, "minimized": false})

private SCREEN = %({"index": 1, "uuid": "37D8832A", "name": "Built-in Retina Display", ) +
                 %("frame": {"x": 0, "y": 0, "w": 1728, "h": 1117}, ) +
                 %("visible_frame": {"x": 0, "y": 38, "w": 1728, "h": 1079}, "scale": 2, "main": true})

private def ok(data : String) : String
  %({"ok": true, "data": #{data}})
end

private def detail(app : SpecHelper::FakeApp) : JSON::Any?
  app.request["detail_data"]?
end

describe "live commands" do
  it "sends one envelope per request: v, event, ts, and no detail_data for status" do
    SpecHelper.sandbox do |sandbox|
      status = ok(%({"version": "0.1.0", "pid": 99, "accessibility": true, "layout_mode": false, ) +
                  %("config": {"path": "/x/config.json", "source": "file", "loaded": true, "error": null}}))
      SpecHelper.with_app(sandbox, {"status" => status}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["status"])
        result.exit_code.should eq(0)
        result.stdout.should contain("accessibility  granted")
        result.stdout.should contain("config         loaded from /x/config.json (file)")

        request = app.request
        request["v"].should eq(1)
        request["event"].should eq("status")
        request["ts"].as_i64.should be_close(Time.utc.to_unix, 60)
        request.as_h.has_key?("detail_data").should be_false
      end
    end
  end

  it "prints the reply's data with --json" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.with_app(sandbox, {"screens" => ok(%({"screens": [#{SCREEN}]}))}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["screens", "--json"])
        result.exit_code.should eq(0)
        result.json["screens"][0]["name"].should eq("Built-in Retina Display")
      end
    end
  end

  it "windows sends only the filters given" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.with_app(sandbox, {"windows" => ok(%({"windows": [#{WINDOW}]}))}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["windows", "--app", "Ghostty", "--screen", "2"])
        result.exit_code.should eq(0)
        result.stdout.should contain("4211")
        result.stdout.should contain("\"kx — zsh\"")
        detail(app).should eq(JSON.parse(%({"app": "Ghostty", "screen": 2})))
      end
    end
  end

  it "place sends a placement with a target and a screen" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.with_app(sandbox, {"place" => ok(%({"window": #{WINDOW}}))}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["place", "left-half", "--app", "Ghostty", "--title", "kx", "--screen", "east"])
        result.exit_code.should eq(0)
        result.stdout.should contain("placed: 4211")
        detail(app).should eq(JSON.parse(
          %({"target": {"app": "Ghostty", "title": "kx"}, "placement": "left-half", "screen": "east"})))
      end
    end
  end

  it "place --rect sends the rect as an object, with a region and a window id" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.with_app(sandbox, {"place" => ok(%({"window": #{WINDOW}}))}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["place", "--rect", "0.5,0,0.5,1", "--region", "gutter", "--window", "4211"])
        result.exit_code.should eq(0)
        SpecHelper.normalize(detail(app).not_nil!).should eq(SpecHelper.normalize(JSON.parse(
          %({"target": {"window_id": 4211}, "rect": {"x": 0.5, "y": 0, "w": 0.5, "h": 1}, "region": "gutter"}))))
      end
    end
  end

  it "place with no target sends no target" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.with_app(sandbox, {"place" => ok(%({"window": #{WINDOW}}))}) do |app|
        SpecHelper.run_live(sandbox, app, ["place", "maximize", "--screen", "2"]).exit_code.should eq(0)
        detail(app).should eq(JSON.parse(%({"placement": "maximize", "screen": 2})))
      end
    end
  end

  it "screen sends screen.move with a direction" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.with_app(sandbox, {"screen.move" => ok(%({"window": #{WINDOW}}))}) do |app|
        SpecHelper.run_live(sandbox, app, ["screen", "west", "--window", "4211"]).exit_code.should eq(0)
        app.request["event"].should eq("screen.move")
        detail(app).should eq(JSON.parse(%({"target": {"window_id": 4211}, "direction": "west"})))
      end
    end
  end

  it "chord sends the canonical keys" do
    SpecHelper.sandbox do |sandbox|
      reply = ok(%({"keys": "ctrl+cmd+h l", "target": {"placement": "left-half"}, "ran": true}))
      SpecHelper.with_app(sandbox, {"chord" => reply}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["chord", "CMD+Ctrl+H l"])
        result.exit_code.should eq(0)
        result.stdout.should contain("ctrl+cmd+h l -> left-half")
        detail(app).should eq(JSON.parse(%({"keys": "ctrl+cmd+h l"})))
      end
    end
  end

  it "reload sends config.reload and fails when the app could not load it" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.with_app(sandbox, {"config.reload" => ok(%({"loaded": false, "error": "bad config"}))}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["reload"])
        result.exit_code.should eq(1)
        result.stderr.should contain("bad config")
        app.request["event"].should eq("config.reload")
      end
    end
  end

  describe "exit codes" do
    it "maps not_permitted to 4" do
      SpecHelper.sandbox do |sandbox|
        refusal = %({"ok": false, "error": "Accessibility permission is not granted", "code": "not_permitted"})
        SpecHelper.with_app(sandbox, {"place" => refusal}) do |app|
          result = SpecHelper.run_live(sandbox, app, ["place", "maximize", "--json"])
          result.exit_code.should eq(4)
          result.stderr.should contain("Accessibility permission is not granted")
          result.json["code"].should eq("not_permitted")
        end
      end
    end

    it "maps ambiguous to 5 and lists the candidates" do
      SpecHelper.sandbox do |sandbox|
        other = WINDOW.sub("4211", "4212").sub("kx — zsh", "notes")
        refusal = %({"ok": false, "error": "2 windows match", "code": "ambiguous", "candidates": [#{WINDOW}, #{other}]})
        SpecHelper.with_app(sandbox, {"place" => refusal}) do |app|
          result = SpecHelper.run_live(sandbox, app, ["place", "maximize", "--app", "Ghostty"])
          result.exit_code.should eq(5)
          result.stderr.should contain("2 windows match")
          result.stderr.should contain("4211")
          result.stderr.should contain("\"notes\"")

          json = SpecHelper.run_live(sandbox, app, ["place", "maximize", "--app", "Ghostty", "--json"])
          json.exit_code.should eq(5)
          json.json["candidates"].as_a.size.should eq(2)
        end
      end
    end

    it "maps not_found to 5 and other codes to 1" do
      SpecHelper.sandbox do |sandbox|
        replies = {
          "screen.move" => %({"ok": false, "error": "no display to the east", "code": "not_found"}),
          "windows"     => %({"ok": false, "error": "no config loaded", "code": "unavailable"}),
          "screens"     => %({"ok": false, "error": "bad", "code": "bad_request"}),
        }
        SpecHelper.with_app(sandbox, replies) do |app|
          SpecHelper.run_live(sandbox, app, ["screen", "east"]).exit_code.should eq(5)
          SpecHelper.run_live(sandbox, app, ["windows"]).exit_code.should eq(1)
          SpecHelper.run_live(sandbox, app, ["screens"]).exit_code.should eq(1)
        end
      end
    end

    it "is 3 when nothing listens, or the app closes without replying" do
      SpecHelper.sandbox do |sandbox|
        down = SpecHelper.run(sandbox, ["status"])
        down.exit_code.should eq(3)
        down.stderr.should contain("not running")

        SpecHelper.with_app(sandbox, {} of String => String) do |app|
          SpecHelper.run_live(sandbox, app, ["status"]).exit_code.should eq(3)
        end
      end
    end

    it "is 2 for a malformed target, without contacting the app" do
      SpecHelper.sandbox do |sandbox|
        SpecHelper.with_app(sandbox, {"place" => ok("{}")}) do |app|
          SpecHelper.run_live(sandbox, app, ["place", "maximize", "--title", "x"]).exit_code.should eq(2)
          SpecHelper.run_live(sandbox, app, ["place", "maximize", "--window", "abc"]).exit_code.should eq(2)
          SpecHelper.run_live(sandbox, app, ["place", "maximize", "--rect", "0,0,1,1"]).exit_code.should eq(2)
          SpecHelper.run_live(sandbox, app, ["place", "--rect", "0,0,2,1"]).exit_code.should eq(2)
          SpecHelper.run_live(sandbox, app, ["screen", "north"]).exit_code.should eq(2)
          app.requests.should be_empty
        end
      end
    end
  end

  describe "config writes" do
    it "send config.reload after writing and report the app's answer" do
      SpecHelper.sandbox do |sandbox|
        SpecHelper.with_app(sandbox, {"config.reload" => ok(%({"loaded": true, "error": null}))}) do |app|
          result = SpecHelper.run_live(sandbox, app, ["bind", "l l", "maximize", "--json"])
          result.exit_code.should eq(0)
          result.json["reload"].should eq(JSON.parse(%({"sent": true, "loaded": true, "error": null})))
          app.request["event"].should eq("config.reload")
          app.request.as_h.has_key?("detail_data").should be_false
        end
      end
    end
  end
end

describe "trellis doctor" do
  it "reports the config and a missing app without failing" do
    SpecHelper.sandbox do |sandbox|
      result = SpecHelper.run(sandbox, ["doctor"])
      result.exit_code.should eq(0)
      result.stdout.should contain("trellis #{Trellis::VERSION}")
      result.stdout.should contain("built-in starter")
      result.stdout.should match(/warn\s+app\s+not running/)
    end
  end

  it "fails on an invalid config" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config("version: 2\n")
      result = SpecHelper.run(sandbox, ["doctor", "--json"])
      result.exit_code.should eq(1)
      result.json["config"]["valid"].should eq(false)
    end
  end

  it "reports the app's version and Accessibility when it answers" do
    SpecHelper.sandbox do |sandbox|
      status = ok(%({"version": "0.0.9", "pid": 99, "accessibility": false, "layout_mode": false, ) +
                  %("config": {"path": "/x", "source": "file", "loaded": true, "error": null}}))
      SpecHelper.with_app(sandbox, {"status" => status}) do |app|
        result = SpecHelper.run_live(sandbox, app, ["doctor"])
        result.exit_code.should eq(1)
        result.stdout.should match(/warn\s+app\s+running, version 0\.0\.9; this CLI is #{Regex.escape(Trellis::VERSION)}/)
        result.stdout.should match(/FAIL\s+accessibility\s+not granted/)
      end
    end
  end
end
