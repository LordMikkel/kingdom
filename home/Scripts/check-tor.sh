#!/usr/bin/env bash
# Check that traffic through proxychains really goes out through Tor.
if proxychains curl --silent https://check.torproject.org/ | grep -q "Congratulations"; then
  echo "✅ Tor is working correctly."
else
  echo "❌ Something gone wrong."
  exit 1
fi
