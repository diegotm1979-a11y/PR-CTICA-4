
with timeout of 600 seconds
    tell application "Numbers"
        activate
        set isOpen to false
        set theDoc to missing value
        repeat with d in documents
            if name of d is "Archivo Individualidades" then
                set isOpen to true
                set theDoc to d
                exit repeat
            end if
        end repeat
        if theDoc is missing value then
            set theDoc to open POSIX file "/Users/diegotueromadiedo/Desktop/BASE DATOS /Archivo Individualidades.numbers"
            set weOpened to true
        else
            set weOpened to false
        end if
        delay 2
        export theDoc to POSIX file "/Users/diegotueromadiedo/Desktop/PRACTICA 4/scripts/_export_cache/Archivo Individualidades.xlsx" as Microsoft Excel
        if weOpened then
            try
                close theDoc saving no
            end try
        end if
    end tell
end timeout
return "ok"
