# Development

Run these commands from this directory:

```sh
bundle install
bundle exec rake
(cd gems/verifiabl-issuer && bundle exec gem build verifiabl-issuer.gemspec)
bundle exec ruby script/packed_gem_check.rb
```

The token store tests that share tokens between processes need Redis. They skip unless
`REDIS_URL` is set; CI sets it. The tests use and clean up their own keys, so a spare database
on a local server works:

```sh
REDIS_URL=redis://127.0.0.1:6379/15 bundle exec rake test
```

## Generated API reference

The public API reference is generated with the pinned [YARD](https://yardoc.org/) dependency. The RBS
signature defines the supported public surface, and YARD supplies documentation from the Ruby source.
Generate the deterministic catalogue with:

```sh
bundle exec ruby script/api_reference.rb
```

The command replaces `generated/api/ruby.json`. The catalogue is checked in so the customer docs can
import an exact SDK revision without running Ruby or accessing this repository at build time. The
default Rake task runs the non-mutating freshness check; it can also be run directly:

```sh
bundle exec ruby script/api_reference.rb --check
```
