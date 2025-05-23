# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

Code.require_file("../../test_helper.exs", __DIR__)

defmodule Mix.Tasks.ReleaseTest do
  use MixTest.Case

  @erts_version :erlang.system_info(:version)
  @hostname :inet_db.gethostname()

  defmacrop release_node(name), do: :"#{name}@#{@hostname}"

  describe "customize" do
    test "env, vm.args and overlays templates" do
      in_fixture("release_test", fn ->
        Mix.Project.in_project(:release_test, ".", fn _ ->
          File.mkdir_p!("rel/overlays/empty/directory")
          File.write!("rel/overlays/hello", "world")

          for file <- ~w(rel/vm.args.eex rel/remote.vm.args.eex rel/env.sh.eex rel/env.bat.eex) do
            File.write!(file, """
            #{file} FOR <%= @release.name %>
            """)
          end

          root = Path.absname("_build/dev/rel/release_test")
          Mix.Task.run("release")
          assert_received {:mix_shell, :info, ["* assembling release_test-0.1.0 on MIX_ENV=dev"]}

          assert root |> Path.join("releases/0.1.0/env.sh") |> File.read!() ==
                   "rel/env.sh.eex FOR release_test\n"

          assert root |> Path.join("releases/0.1.0/env.bat") |> File.read!() ==
                   "rel/env.bat.eex FOR release_test\n"

          assert root |> Path.join("releases/0.1.0/vm.args") |> File.read!() ==
                   "rel/vm.args.eex FOR release_test\n"

          assert root |> Path.join("releases/0.1.0/remote.vm.args") |> File.read!() ==
                   "rel/remote.vm.args.eex FOR release_test\n"

          assert root |> Path.join("empty/directory") |> File.dir?()
          assert root |> Path.join("hello") |> File.read!() == "world"
        end)
      end)
    end

    test "env, vm.args and overlays templates with custom rel_templates_path" do
      in_fixture("release_test", fn ->
        config = [
          releases: [
            release_test: [rel_templates_path: "custom_rel"]
          ]
        ]

        Mix.Project.in_project(:release_test, ".", config, fn _ ->
          File.mkdir_p!("custom_rel/overlays/empty/directory")
          File.write!("custom_rel/overlays/hello", "world")

          for file <-
                ~w(custom_rel/vm.args.eex custom_rel/remote.vm.args.eex custom_rel/env.sh.eex custom_rel/env.bat.eex) do
            File.write!(file, """
            #{file} FOR <%= @release.name %>
            """)
          end

          root = Path.absname("_build/dev/rel/release_test")
          Mix.Task.run("release")
          assert_received {:mix_shell, :info, ["* assembling release_test-0.1.0 on MIX_ENV=dev"]}

          assert root |> Path.join("releases/0.1.0/env.sh") |> File.read!() ==
                   "custom_rel/env.sh.eex FOR release_test\n"

          assert root |> Path.join("releases/0.1.0/env.bat") |> File.read!() ==
                   "custom_rel/env.bat.eex FOR release_test\n"

          assert root |> Path.join("releases/0.1.0/vm.args") |> File.read!() ==
                   "custom_rel/vm.args.eex FOR release_test\n"

          assert root |> Path.join("releases/0.1.0/remote.vm.args") |> File.read!() ==
                   "custom_rel/remote.vm.args.eex FOR release_test\n"

          assert root |> Path.join("empty/directory") |> File.dir?()
          assert root |> Path.join("hello") |> File.read!() == "world"
        end)
      end)
    end

    test "custom overlays" do
      in_fixture("release_test", fn ->
        config = [releases: [release_test: [overlays: "rel/another"]]]

        Mix.Project.in_project(:release_test, ".", config, fn _ ->
          File.mkdir_p!("rel/overlays")
          File.write!("rel/overlays/hello", "world")
          File.write!("rel/overlays/original", "kept")

          File.mkdir_p!("rel/another/empty/directory")
          File.write!("rel/another/hello", "override")

          root = Path.absname("_build/dev/rel/release_test")
          Mix.Task.rerun("release", ["--overwrite"])

          assert root |> Path.join("empty/directory") |> File.dir?()
          assert root |> Path.join("hello") |> File.read!() == "override"
          assert root |> Path.join("original") |> File.read!() == "kept"
        end)
      end)
    end

    test "steps" do
      in_fixture("release_test", fn ->
        last_step = fn release ->
          send(self(), {:last_step, release})
          release
        end

        first_step = fn release ->
          send(self(), {:first_step, release})
          update_in(release.steps, &(&1 ++ [last_step]))
        end

        config = [releases: [demo: [steps: [first_step, :assemble]]]]

        Mix.Project.in_project(:release_test, ".", config, fn _ ->
          Mix.Task.run("release")
          assert_received {:mix_shell, :info, ["* assembling demo-0.1.0 on MIX_ENV=dev"]}

          # Discard info messages from inbox for upcoming assertions
          Mix.shell().flush(& &1)

          {:messages,
           [
             {:first_step, %Mix.Release{steps: [:assemble]}},
             {:last_step, %Mix.Release{steps: []}}
           ]} = Process.info(self(), :messages)
        end)
      end)
    end

    test "include_executables_for and strip_beams" do
      in_fixture("release_test", fn ->
        config = [
          releases: [
            release_test: [
              include_executables_for: [],
              strip_beams: [keep: "Docs"]
            ]
          ]
        ]

        Mix.Project.in_project(:release_test, ".", config, fn _ ->
          root = Path.absname("_build/dev/rel/release_test")
          Mix.Task.run("release")
          assert_received {:mix_shell, :info, ["* assembling release_test-0.1.0 on MIX_ENV=dev"]}

          beam =
            File.read!(Path.join(root, "lib/release_test-0.1.0/ebin/Elixir.ReleaseTest.beam"))

          assert {:ok, {_, [{~c"Docs", _}]}} = :beam_lib.chunks(beam, [~c"Docs"])
          assert {:error, _, _} = :beam_lib.chunks(beam, [~c"Dbgi"])

          refute root |> Path.join("bin/start") |> File.exists?()
          refute root |> Path.join("bin/start.bat") |> File.exists?()
          refute root |> Path.join("releases/0.1.0/elixir") |> File.exists?()
          refute root |> Path.join("releases/0.1.0/elixir.bat") |> File.exists?()
          refute root |> Path.join("releases/0.1.0/iex") |> File.exists?()
          refute root |> Path.join("releases/0.1.0/iex.bat") |> File.exists?()
        end)
      end)
    end
  end

  describe "errors" do
    test "requires a matching name" do
      in_fixture("release_test", fn ->
        Mix.Project.in_project(:release_test, ".", fn _ ->
          assert_raise Mix.Error, ~r"Unknown release :unknown", fn ->
            Mix.Task.run("release", ["unknown"])
          end
        end)
      end)
    end
  end

  describe "tar" do
    test "with default options" do
      in_fixture("release_test", fn ->
        config = [releases: [demo: [steps: [:assemble, :tar]]]]

        Mix.Project.in_project(:release_test, ".", config, fn _ ->
          root = Path.absname("_build/#{Mix.env()}/rel/demo")

          ignored_app_path = Path.join([root, "lib", "ignored_app-0.1.0", "ebin"])
          File.mkdir_p!(ignored_app_path)
          File.touch(Path.join(ignored_app_path, "ignored_app.app"))

          ignored_release_path = Path.join([root, "releases", "ignored_dir"])
          File.mkdir_p!(ignored_release_path)
          File.touch(Path.join(ignored_release_path, "ignored"))

          # Overlays
          File.mkdir_p!("rel/overlays/empty/directory")
          File.write!("rel/overlays/hello", "world")

          Mix.Task.run("release")
          tar_path = Path.expand(Path.join([root, "..", "..", "demo-0.1.0.tar.gz"]))
          message = "* building #{tar_path}"
          assert_received {:mix_shell, :info, [^message]}
          assert File.exists?(tar_path)

          {:ok, files} = String.to_charlist(tar_path) |> :erl_tar.table([:compressed])

          files = Enum.map(files, &to_string/1)
          files_with_versions = File.ls!(Path.join(root, "lib"))

          assert "bin/demo" in files
          assert "releases/0.1.0/sys.config" in files
          assert "releases/0.1.0/vm.args" in files
          assert "releases/0.1.0/remote.vm.args" in files
          assert "releases/COOKIE" in files
          assert "releases/start_erl.data" in files
          assert "hello" in files
          assert "empty/directory" in files
          assert Enum.any?(files, &(&1 =~ "erts"))
          assert Enum.any?(files, &(&1 =~ "stdlib"))

          for dir <- files_with_versions -- ["ignored_app-0.1.0"] do
            [name | _] = String.split(dir, "-")
            assert "lib/#{dir}/ebin/#{name}.app" in files
          end

          refute "lib/ignored_app-0.1.0/ebin/ignored_app.app" in files
          refute "releases/ignored_dir/ignored" in files
        end)
      end)
    end

    test "without ERTS and custom path" do
      in_fixture("release_test", fn ->
        config = [
          releases: [demo: [include_erts: false, path: "tmp/rel", steps: [:assemble, :tar]]]
        ]

        Mix.Project.in_project(:release_test, ".", config, fn _ ->
          Mix.Task.run("release")
          tar_path = Path.expand(Path.join(["tmp", "rel", "demo-0.1.0.tar.gz"]))
          message = "* building #{tar_path}"
          assert_received {:mix_shell, :info, [^message]}
          assert File.exists?(tar_path)

          {:ok, files} = String.to_charlist(tar_path) |> :erl_tar.table([:compressed])
          files = Enum.map(files, &to_string/1)

          assert "bin/demo" in files
          refute Enum.any?(files, &(&1 =~ "erts"))
          refute Enum.any?(files, &(&1 =~ "stdlib"))
        end)
      end)
    end

    test "without ERTS when a previous build included ERTS" do
      in_fixture("release_test", fn ->
        config = [releases: [demo: [include_erts: false, steps: [:assemble, :tar]]]]

        Mix.Project.in_project(:release_test, ".", config, fn _ ->
          root = Path.absname("_build/#{Mix.env()}/rel/demo")

          erts_dir_from_previous_build =
            Path.absname("_build/#{Mix.env()}/rel/demo/erts-#{@erts_version}")

          File.mkdir_p!(erts_dir_from_previous_build)

          Mix.Task.run("release")
          tar_path = Path.expand(Path.join([root, "..", "..", "demo-0.1.0.tar.gz"]))
          message = "* building #{tar_path}"
          assert_received {:mix_shell, :info, [^message]}
          assert File.exists?(tar_path)

          {:ok, files} = String.to_charlist(tar_path) |> :erl_tar.table([:compressed])
          files = Enum.map(files, &to_string/1)

          assert "bin/demo" in files
          refute Enum.any?(files, &(&1 =~ "erts"))
          refute Enum.any?(files, &(&1 =~ "stdlib"))
        end)
      end)
    end
  end

  test "assembles a bootable release with ERTS" do
    in_fixture("release_test", fn ->
      Mix.Project.in_project(:release_test, ".", fn _ ->
        root = Path.absname("_build/dev/rel/release_test")

        # Assert command
        Mix.Task.run("release")
        assert_received {:mix_shell, :info, ["* assembling release_test-0.1.0 on MIX_ENV=dev"]}

        assert_received {:mix_shell, :info,
                         ["\nRelease created at _build/dev/rel/release_test\n" <> _]}

        assert_received {:mix_shell, :info, ["* skipping runtime configuration" <> _]}

        # Assert structure
        assert root |> Path.join("erts-#{@erts_version}") |> File.exists?()
        assert root |> Path.join("lib/release_test-0.1.0/ebin") |> File.exists?()
        assert root |> Path.join("lib/release_test-0.1.0/priv/hello") |> File.exists?()
        assert root |> Path.join("releases/COOKIE") |> File.exists?()
        assert root |> Path.join("releases/start_erl.data") |> File.exists?()
        assert root |> Path.join("releases/0.1.0/release_test.rel") |> File.exists?()
        assert root |> Path.join("releases/0.1.0/sys.config") |> File.exists?()
        assert root |> Path.join("releases/0.1.0/env.sh") |> File.exists?()
        assert root |> Path.join("releases/0.1.0/env.bat") |> File.exists?()
        assert root |> Path.join("releases/0.1.0/vm.args") |> File.exists?()
        assert root |> Path.join("releases/0.1.0/remote.vm.args") |> File.exists?()

        assert root
               |> Path.join("releases/0.1.0/sys.config")
               |> File.read!() =~ "RUNTIME_CONFIG=false"

        assert root
               |> Path.join("lib/release_test-0.1.0/priv")
               |> File.read_link()
               |> elem(0) == :error

        cookie = File.read!(Path.join(root, "releases/COOKIE"))

        # Assert runtime
        open_port(Path.join(root, "bin/release_test"), [~c"start"])

        assert %{
                 app_dir: app_dir,
                 cookie_env: ^cookie,
                 encoding: {:_μ, :"£", "£", ~c"£"},
                 mode: :embedded,
                 node: release_node("release_test"),
                 protocols_consolidated?: true,
                 release_name: "release_test",
                 release_node: "release_test",
                 release_prog: "release_test" <> ext,
                 release_root: release_root,
                 release_vsn: "0.1.0",
                 root_dir: root_dir,
                 runtime_config: :error,
                 static_config: {:ok, :was_set},
                 sys_config_env: sys_config_env,
                 sys_config_init: sys_config_init
               } = wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))

        if match?({:win32, _}, :os.type()) do
          # `RELEAS~1` is the DOS path name (8 character) for the `release_test` directory
          assert app_dir =~ ~r"_build/dev/rel/(release_test|RELEAS~1)/lib/release_test-0\.1\.0$"
          assert release_root =~ ~r"_build\\dev\\rel\\(release_test|RELEAS~1)$"
          assert root_dir =~ ~r"_build/dev/rel/(release_test|RELEAS~1)$"
          assert String.ends_with?(sys_config_env, "releases\\0.1.0\\sys")
          assert String.ends_with?(sys_config_init, "releases\\0.1.0\\sys")
          assert ext == ".bat"
        else
          assert app_dir == Path.join(root, "lib/release_test-0.1.0")
          assert release_root == root
          assert root_dir == root
          assert sys_config_env == Path.join(root, "releases/0.1.0/sys")
          assert sys_config_init == Path.join(root, "releases/0.1.0/sys")
          assert ext == ""
        end
      end)
    end)
  end

  test "assembles a rebootable release with runtime configuration" do
    in_fixture("release_test", fn ->
      config = [releases: [runtime_config: [reboot_system_after_config: true]]]

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        File.write!("config/config.exs", """
        #{File.read!("config/config.exs")}
        config :release_test, :runtime, keep: :static, override: :static
        """)

        File.write!("config/runtime.exs", """
        import Config

        if System.get_env("RELEASE_MODE") == nil do
          raise "file should not be loaded while assembling release"
        end

        # Ensure app has been loaded
        [_ | _] = Application.spec(:release_test, :modules)

        config :release_test, :runtime,
          override: :runtime,
          config_env: config_env(),
          config_target: config_target(),
          mode: :code.get_mode()

        config :release_test, :encoding, {:runtime, :_μ, :"£", "£", ~c"£"}
        """)

        root = Path.absname("_build/dev/rel/runtime_config")

        # Assert command
        Mix.Task.run("release", ["runtime_config"])
        assert_received {:mix_shell, :info, ["* assembling runtime_config-0.1.0 on MIX_ENV=dev"]}

        assert_received {:mix_shell, :info,
                         ["* using config/runtime.exs to configure the release at runtime"]}

        # Assert structure
        assert root
               |> Path.join("releases/0.1.0/sys.config")
               |> File.read!() =~ "RUNTIME_CONFIG=true"

        # Make sys.config read-only and it should still boot
        assert root
               |> Path.join("releases/0.1.0/sys.config")
               |> File.chmod(0o555) == :ok

        # Assert runtime
        open_port(Path.join(root, "bin/runtime_config"), [~c"start"])

        assert %{
                 encoding: {:runtime, :_μ, :"£", "£", ~c"£"},
                 mode: :embedded,
                 node: release_node("runtime_config"),
                 protocols_consolidated?: true,
                 release_name: "runtime_config",
                 release_mode: "embedded",
                 release_node: "runtime_config",
                 release_prog: "runtime_config" <> ext,
                 release_vsn: "0.1.0",
                 runtime_config:
                   {:ok,
                    [
                      keep: :static,
                      override: :runtime,
                      config_env: :dev,
                      config_target: :host,
                      mode: :interactive
                    ]},
                 static_config: {:ok, :was_set},
                 sys_config_env: sys_config_env,
                 sys_config_init: sys_config_init
               } = wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))

        if match?({:win32, _}, :os.type()) do
          assert sys_config_env =~ "tmp\\runtime_config-0.1.0"
          assert sys_config_init =~ "tmp\\runtime_config-0.1.0"
          assert ext == ".bat"
        else
          assert sys_config_env =~ "tmp/runtime_config-0.1.0"
          assert sys_config_init =~ "tmp/runtime_config-0.1.0"
          assert ext == ""
        end
      end)
    end)
  end

  test "assembles a bootable release without distribution" do
    in_fixture("release_test", fn ->
      config = [releases: [no_dist: []]]

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        root = Path.absname("_build/dev/rel/no_dist")
        Mix.Task.run("release", ["no_dist"])

        open_port(Path.join(root, "bin/no_dist"), [~c"start"], [
          {~c"RELEASE_DISTRIBUTION", ~c"none"}
        ])

        assert %{
                 mode: :embedded,
                 node: :nonode@nohost,
                 protocols_consolidated?: true,
                 release_name: "no_dist",
                 release_node: "no_dist",
                 release_vsn: "0.1.0"
               } = wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))
      end)
    end)
  end

  test "assembles a release without ERTS and with custom options" do
    in_fixture("release_test", fn ->
      config = [releases: [demo: [include_erts: false, cookie: "abcdefghijk"]]]

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        root = Path.absname("demo")

        Mix.Task.run("release", ["demo", "--path", "demo", "--version", "0.2.0", "--quiet"])
        refute_received {:mix_shell, :info, ["* assembling " <> _]}
        refute_received {:mix_shell, :info, ["\nRelease created " <> _]}

        # Assert structure
        assert root |> Path.join("bin/demo") |> File.exists?()
        refute root |> Path.join("erts-#{@erts_version}") |> File.exists?()
        assert root |> Path.join("lib/release_test-0.1.0/ebin") |> File.exists?()
        assert root |> Path.join("lib/release_test-0.1.0/priv/hello") |> File.exists?()
        assert root |> Path.join("releases/COOKIE") |> File.exists?()
        assert root |> Path.join("releases/start_erl.data") |> File.exists?()
        assert root |> Path.join("releases/0.2.0/demo.rel") |> File.exists?()
        assert root |> Path.join("releases/0.2.0/sys.config") |> File.exists?()
        assert root |> Path.join("releases/0.2.0/vm.args") |> File.exists?()
        assert root |> Path.join("releases/0.2.0/remote.vm.args") |> File.exists?()

        # Assert runtime
        open_port(Path.join(root, "bin/demo"), [~c"start"])

        assert %{
                 app_dir: app_dir,
                 cookie_env: "abcdefghijk",
                 mode: :embedded,
                 node: release_node("demo"),
                 protocols_consolidated?: true,
                 release_name: "demo",
                 release_node: "demo",
                 release_prog: "demo" <> ext,
                 release_root: release_root,
                 release_vsn: "0.2.0",
                 root_dir: root_dir,
                 runtime_config: :error,
                 static_config: {:ok, :was_set}
               } = wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))

        if match?({:win32, _}, :os.type()) do
          assert String.ends_with?(app_dir, "demo/lib/release_test-0.1.0")
          assert String.ends_with?(release_root, "demo")
          assert ext == ".bat"
        else
          assert app_dir == Path.join(root, "lib/release_test-0.1.0")
          assert release_root == root
          assert ext == ""
        end

        assert root_dir == :code.root_dir() |> to_string()
      end)
    end)
  end

  test "validates compile_env" do
    in_fixture("release_test", fn ->
      # Let's also use a non standard config_path.
      config = [releases: [compile_env_config: []], config_path: "different_config/config.exs"]

      File.write!("lib/compile_env.ex", """
      require Application
      _ = Application.compile_env(:release_test, :static)
      """)

      File.mkdir_p!("different_config")
      File.cp!("config/config.exs", "different_config/config.exs")

      File.write!("different_config/runtime.exs", """
      import Config
      config :release_test, :static, String.to_atom(System.get_env("RELEASE_STATIC"))
      """)

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        Mix.Task.run("loadconfig", [])

        root = Path.absname("_build/dev/rel/compile_env_config")
        Mix.Task.run("release", ["compile_env_config"])

        assert {output, _} =
                 System.cmd(Path.join(root, "bin/compile_env_config"), ["start"],
                   stderr_to_stdout: true,
                   env: [{"RELEASE_STATIC", "runtime"}]
                 )

        assert output =~
                 "ERROR! the application :release_test has a different value set for key :static during runtime compared to compile time"

        # But now it does
        env = [{~c"RELEASE_STATIC", ~c"was_set"}]
        open_port(Path.join(root, "bin/compile_env_config"), [~c"start"], env)
        assert %{} = wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))
      end)
    end)
  end

  test "does not validate compile_env if opted out" do
    in_fixture("release_test", fn ->
      config = [releases: [no_compile_env_config: [validate_compile_env: false]]]

      File.write!("lib/compile_env.ex", """
      require Application
      _ = Application.compile_env(:release_test, :static)
      """)

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        Mix.Task.run("loadconfig", [])

        File.write!("config/runtime.exs", """
        import Config
        config :release_test, :static, String.to_atom(System.get_env("RELEASE_STATIC"))
        config :release_test, :runtime, mode: :code.get_mode()
        """)

        root = Path.absname("_build/dev/rel/no_compile_env_config")
        Mix.Task.run("release", ["no_compile_env_config"])

        # It boots with mismatched config
        env = [{~c"RELEASE_STATIC", ~c"runtime"}]
        open_port(Path.join(root, "bin/no_compile_env_config"), [~c"start"], env)

        assert %{
                 mode: :embedded,
                 runtime_config: {:ok, [mode: :embedded]},
                 static_config: {:ok, :runtime}
               } =
                 wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))
      end)
    end)
  end

  @tag :epmd
  test "executes rpc instructions" do
    in_fixture("release_test", fn ->
      config = [releases: [permanent1: [include_erts: false]]]

      # We write the compile env to guarantee rpc still works
      File.write!("lib/compile_env.ex", """
      require Application
      _ = Application.compile_env(:release_test, :static)
      """)

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        Mix.Task.run("loadconfig", [])

        # For compile env to be validated, we need a config/runtime.exs
        File.write!("config/runtime.exs", """
        import Config
        """)

        root = Path.absname("_build/dev/rel/permanent1")
        Mix.Task.run("release")
        script = Path.join(root, "bin/permanent1")

        env = [{"RELEASE_DISTRIBUTION", "name"}, {"RELEASE_NODE", "permanent1@127.0.0.1"}]
        open_port(script, [~c"start"], env)
        wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))

        assert System.cmd(script, ["rpc", "ReleaseTest.hello_world()"], env: env) ==
                 {"hello world\n", 0}

        assert {pid, 0} = System.cmd(script, ["pid"], env: env)
        assert pid != "\n"

        assert System.cmd(script, ["stop"], env: env) == {"", 0}
      end)
    end)
  end

  test "runs eval and version commands" do
    # In some Windows setups (mostly with Docker), `System.cmd/3` fails because
    # the path to the command/executable and one or more arguments contain spaces.
    tmp_dir = Path.join(inspect(__MODULE__), "runs_eval_and_version_commands")

    in_fixture("release_test", tmp_dir, fn ->
      config = [releases: [eval: [include_erts: false, cookie: "abcdefghij"]]]

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        File.write!("config/runtime.exs", """
        import Config

        config :release_test, :runtime, [mode: :code.get_mode()]

        # Ensure app has been loaded
        [_ | _] = Application.spec(:release_test, :modules)
        """)

        root = Path.absname("_build/dev/rel/eval")
        Mix.Task.run("release")

        script = Path.join(root, "bin/eval")
        {version, 0} = System.cmd(script, ["version"])
        assert String.trim_trailing(version) == "eval 0.1.0"
        refute File.exists?(Path.join(root, "RELEASE_BOOTED"))

        {hello_world, 0} = System.cmd(script, ["eval", "IO.puts :hello_world"])
        assert String.trim_trailing(hello_world) == "hello_world"
        refute File.exists?(Path.join(root, "RELEASE_BOOTED"))

        {hello_world, 0} =
          System.cmd(script, ["eval", "IO.inspect(System.argv( ))", "a", "b", "c"])

        assert String.trim_trailing(hello_world) == ~S(["a", "b", "c"])
        refute File.exists?(Path.join(root, "RELEASE_BOOTED"))

        open_port(script, [~c"eval", ~c"Application.ensure_all_started(:release_test)"])

        assert %{
                 cookie_env: "abcdefghij",
                 mode: :interactive,
                 node: :nonode@nohost,
                 protocols_consolidated?: true,
                 release_name: "eval",
                 release_node: "eval",
                 release_prog: "eval" <> ext,
                 release_root: release_root,
                 release_vsn: "0.1.0",
                 runtime_config: {:ok, [mode: :interactive]},
                 static_config: {:ok, :was_set}
               } = wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))

        if match?({:win32, _}, :os.type()) do
          assert String.ends_with?(release_root, "eval")
          assert ext == ".bat"
        else
          assert release_root == root
          assert ext == ""
        end
      end)
    end)
  end

  @tag :unix
  test "runs in daemon mode" do
    in_fixture("release_test", fn ->
      config = [releases: [permanent2: [include_erts: false, cookie: "abcdefghij"]]]

      Mix.Project.in_project(:release_test, ".", config, fn _ ->
        root = Path.absname("_build/dev/rel/permanent2")
        Mix.Task.run("release")

        script = Path.join(root, "bin/permanent2")
        env = [{"RELEASE_DISTRIBUTION", "name"}, {"RELEASE_NODE", "permanent2@127.0.0.1"}]
        open_port(script, [~c"daemon_iex"], env)

        assert %{
                 app_dir: app_dir,
                 cookie_env: "abcdefghij",
                 mode: :embedded,
                 node: :"permanent2@127.0.0.1",
                 protocols_consolidated?: true,
                 release_name: "permanent2",
                 release_node: "permanent2@127.0.0.1",
                 release_root: ^root,
                 release_vsn: "0.1.0",
                 root_dir: root_dir,
                 runtime_config: :error,
                 static_config: {:ok, :was_set},
                 sys_config_env: sys_config_env,
                 sys_config_init: sys_config_init
               } = wait_until_decoded(Path.join(root, "RELEASE_BOOTED"))

        assert app_dir == Path.join(root, "lib/release_test-0.1.0")
        assert root_dir == :code.root_dir() |> to_string()
        assert sys_config_env == Path.join(root, "releases/0.1.0/sys")
        assert sys_config_init == Path.join(root, "releases/0.1.0/sys")

        assert wait_until(fn ->
                 File.read!(Path.join(root, "tmp/log/erlang.log.1")) =~
                   "iex(permanent2@127.0.0.1)1> "
               end)

        assert System.cmd(script, ["rpc", "ReleaseTest.hello_world()"], env: env) ==
                 {"hello world\n", 0}

        assert System.cmd(script, ["restart"], env: env) == {"", 0}

        assert wait_until(fn ->
                 File.read!(Path.join(root, "tmp/log/erlang.log.1")) =~
                   "RESTARTED!!!"
               end)

        assert System.cmd(script, ["stop"], env: env) == {"", 0}
      end)
    end)
  end

  test "requires confirmation if release already exists unless overwriting" do
    in_fixture("release_test", fn ->
      Mix.Project.in_project(:release_test, ".", fn _ ->
        Mix.Task.rerun("release")
        assert_received {:mix_shell, :info, ["* assembling release_test-0.1.0 on MIX_ENV=dev"]}

        send(self(), {:mix_shell_input, :yes?, false})
        Mix.Task.rerun("release")
        refute_received {:mix_shell, :info, ["* assembling release_test-0.1.0 on MIX_ENV=dev"]}

        assert_received {:mix_shell, :yes?,
                         ["Release release_test-0.1.0 already exists. Overwrite?"]}

        Mix.Task.rerun("release", ["--overwrite"])
        assert_received {:mix_shell, :info, ["* assembling release_test-0.1.0 on MIX_ENV=dev"]}
      end)
    end)
  end

  @tag :unix
  test "works properly with an absolute symlink to release" do
    in_fixture("release_test", fn ->
      Mix.Project.in_project(:release_test, ".", fn _ ->
        Mix.Task.run("release")

        File.ln_s!(
          Path.absname("_build/#{Mix.env()}/rel/release_test/bin/release_test"),
          Path.absname("release_test")
        )

        script = Path.absname("release_test")
        {hello_world, 0} = System.cmd(script, ["eval", "IO.puts :hello_world"])
        assert String.trim_trailing(hello_world) == "hello_world"
      end)
    end)
  end

  @tag :unix
  test "works properly with a relative symlink to release" do
    in_fixture("release_test", fn ->
      Mix.Project.in_project(:release_test, ".", fn _ ->
        Mix.Task.run("release")

        File.mkdir!("bin")
        File.ln_s!("../_build/#{Mix.env()}/rel/release_test/bin/release_test", "bin/release_test")

        script = Path.absname("bin/release_test")
        {hello_world, 0} = System.cmd(script, ["eval", "IO.puts :hello_world"])
        assert String.trim_trailing(hello_world) == "hello_world"
      end)
    end)
  end

  defp open_port(command, args, env \\ []) do
    env = for {k, v} <- env, do: {to_charlist(k), to_charlist(v)}
    Port.open({:spawn_executable, to_charlist(command)}, [:hide, args: args, env: env])
  end

  defp wait_until_decoded(file) do
    wait_until(fn ->
      case File.read(file) do
        {:ok, bin} when byte_size(bin) > 0 -> :erlang.binary_to_term(bin)
        _ -> nil
      end
    end)
  end

  defp wait_until(fun) do
    if value = fun.() do
      value
    else
      Process.sleep(10)
      wait_until(fun)
    end
  end
end
