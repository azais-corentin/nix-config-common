# Claude usage estimator TUI and `get` CLI. Both read the forecasts served by
# the daemon (http://vega:7781 by default, or $CLAUDE_USAGE_SERVER).
{ pkgs, ... }:
{
  home.packages = [ pkgs.inputs.claude-usage-estimator.default ];
}
