-- Source for ~/Applications/YonseiJobFetch.app, a tiny local launcher
-- registered to the yonseijobfetch:// custom URL scheme (see Info.plist
-- editing in the setup steps). No Dock icon (LSUIElement), runs silently.
--
-- Backgrounds the actual script (trailing "&", output redirected to a log
-- file) rather than waiting for it, since walking every one of today's
-- postings individually can take a while -- the site's "AI Job Fetch"
-- button just needs to hand off and return immediately, not block on it.
on open location this_URL
	do shell script "cd " & quoted form of "/Users/kristoffertiedemann/Desktop/Personal/Productivity Tracker - Website Builder/scripts" & " && /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 yonsei_jobboard_detail_fetch.py > /tmp/yonsei_jobboard_detail_fetch.log 2>&1 &"
end open location
