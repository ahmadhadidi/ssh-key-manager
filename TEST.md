# Run Tests
``` bash
# Run all Remote
pytest tests/*_remote_*.py

# Run all Local
pytest tests/*_local_*.py

# Run all Config
pytest tests/*_config_*.py
```

# The "Total" Run
> To run everything in order and get a full report:
``` bash
pytest tests/ -v
```

# Fail Fast
> If you're developing and want the tests to stop the moment one of them fails (so you can fix it immediately):

``` bash
pytest tests/ -x
```

# See the TUI during the test
> If a test fails and you want to see the actual "live" render of the TUI during the automated run, use the -s flag:
``` bash
pytest tests/01_remote_generate_and_install.py -s
```