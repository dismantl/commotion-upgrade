function lprint(msg) {
  print msg | "tee " LOG
}
function fail(code, msg) {
  lprint(msg)
  while ((getline f < BACKUPS) > 0)
    system("ls \"" f ".commotion-backup\" 2>&1 1> /dev/null && mv \"" f ".commotion-backup\" \"" f "\"")
  close(BACKUPS)
  system("rm -f " BACKUPS)
  exit code
}
BEGIN {
  FS=":\\s*"
  if (!SCRIPTS_DIR ||
      !ERR_PARSE ||
      !ERR_RUN ||
      !BACKUPS ||
      !LOG)
    fail(1, "Missing required variables for manifest parsing script")
  "cat /etc/openwrt_version |grep -o [0-9.]*" | getline current_version
}
function set_param(key, val) {
  if (val)
    script[key] = val
}
function append_param(key, val) {
  script[key] = script[key] (script[key] ? "\n" : "") val
}
function new_script(filename) {
  script["filename"]=filename
  script["description"]=""
  multiline=""
}
function check_complete() {
  if (script["filename"]) {
    if (!compatible) {
      lprint("Script " script["filename"] " not compatible with this version of Commotion; skipping...")
    } else {
      lprint("Running script " script["filename"] ((script["description"]) ? "\ndescription: \"" script["description"] "\"" : ""))
      code = system("chmod +x \"" SCRIPTS_DIR "/" script["filename"] "\" && \"" SCRIPTS_DIR "/" script["filename"] "\" 2>&1 1>> " LOG)
      if (code != 0)
	fail(ERR_RUN, "ERROR: Script " script["filename"] " exited with code " code ". Affected files have been restored. See " LOG " for details.")
    }
  }
}
/^filename:\s*.+$/ {
  check_complete()
  compatible=0; multiline=""
  if (system("ls \"" SCRIPTS_DIR "/" $2 "\" 2>&1 1> /dev/null") != 0)
    fail(ERR_PARSE, "Script file " $2 " does not exist")
  new_script($2)
}
/^commotion versions:\s*[-0-9.\,<>= ]+\s*$/ {
  multiline=""
  split($2,versions,",")
  for (i in versions) {
    version = versions[i]
    if ((sub(/^\s*<=\s*/,"",version) == 1 && current_version <= version) ||
        (sub(/^\s*>=\s*/,"",version) == 1 && current_version >= version) ||
	(sub(/^\s*<\s*/,"",version) == 1 && current_version < version) ||
        (sub(/^\s*>\s*/,"",version) == 1 && current_version > version) ||
        (match(version, /^[0-9.]+-[0-9.]+$/) > 0 &&
	  split(version, range, "-") == 2 &&
	  current_version >= range[1] &&
	  current_version <= range[2]) ||
	(match(version, /^[0-9.]+$/) > 0 && current_version == version))
      compatible = 1
  }
}
{ if (!compatible) next }
/^sha1sum:\s*[[:xdigit:]]{40}\s*$/ {
  multiline=""
  "sha1sum \"" SCRIPTS_DIR "/" script["filename"] "\" |grep -o ^[[:xdigit:]]*" | getline sum
  close("sha1sum \"" SCRIPTS_DIR "/" script["filename"] "\" |grep -o ^[[:xdigit:]]*")
  if (!match($2, sum))
    fail(ERR_PARSE, "Invalid SHA1 sum for script " script["filename"])
}
/^description:.*$/ {
  multiline="description"
  next
}
/^supporting files:\s*$/ {
  multiline="supporting"
  next
}
/^affected files:\s*$/ {
  multiline="affected"
  next
}
{
  if (multiline == "description") {
    append_param("description", gensub(/^\s*(.*)$/,"\\1",1))
  } else if (!$0) {
    next
  } else if (multiline == "supporting") {
    if (!match($0, /^\s*(.+)\s+([[:xdigit:]]{40})\s*$/))
      fail(ERR_PARSE, "Error parsing supporting files list for script " script["filename"] ": " $0)
    f = gensub(/^\s*(.+)\s+([[:xdigit:]]{40})\s*$/, "\\1", 1) # b/c busybox match() won't fill capture array
    s = gensub(/^\s*(.+)\s+([[:xdigit:]]{40})\s*$/, "\\2", 1)
    "sha1sum \"" SCRIPTS_DIR "/files/" f "\" |grep -o ^[[:xdigit:]]*" | getline sum
    close("sha1sum \"" SCRIPTS_DIR "/files/" f "\" |grep -o ^[[:xdigit:]]*")
    if (!match(s, sum))
      fail(ERR_PARSE, "Invalid SHA1 sum for supporting file " f " for script " script["filename"])
  } else if (multiline == "affected") {
    f = gensub(/^\s*(.+)\s*$/, "\\1", 1)
    print f >> BACKUPS
    system("cp \"" f "\" \"" f ".commotion-backup\"") # okay if cp fails in case file doesnt exist
  }
}
END { check_complete() }