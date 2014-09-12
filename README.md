# LINC Configuration generator


Utility that takes a JSON topology description file and generates a `sys.config` configuration file for the [LINC Switch](http://github.com/FlowForwarding/LINC-Switch).

## Usage

Compile with:

```
$ ./rebar get-deps compile
```

Start the Erlang shell:

```
$ erl -pa deps/jsx/ebin ebin

Eshell V5.10.4  (abort with ^G)
1> config_generator:parse("json_example.json", "sys.config.template", "localhost", 4343).
ok
```

This will generate a `sys.config` file.
