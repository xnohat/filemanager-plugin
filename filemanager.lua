VERSION = "2.1.0"

treeView = nil
cwd = WorkingDirectory()
driveLetter = "C:\\"
isWin = (OS == "windows")
debug = true
files = {}

function debugInfo(log)
    if debug == true then
        messenger:AddLog("Filemanager plugin : " .. log)
    end
end

-- ToggleTree will toggle the tree view visible (create) and hide (delete).
function ToggleTree()
    debugInfo("Function --> ToggleTree()")
    if treeView == nil then
        OpenTree()
    else
        CloseTree()
    end
end

-- OpenTree setup's the view
function OpenTree()
    debugInfo("Function --> OpenTree()")
    CurView():VSplitIndex(NewBuffer("", "FileManager"), 0)
    setupOptions()
    refreshTree()
end

-- setupOptions setup tree view options
function setupOptions()
    debugInfo("Function --> setupOptions()")
    treeView = CurView()
    treeView.Width = 30
    treeView.LockWidth = true
    -- set options for tree view
    status = SetLocalOption("ruler", "false", treeView)
    if status ~= nil then
        messenger:Error("Error setting ruler option -> ", status)
    end
    status = SetLocalOption("softwrap", "true", treeView)
    if status ~= nil then
        messenger:Error("Error setting softwrap option -> ", status)
    end
    status = SetLocalOption("autosave", "false", treeView)
    if status ~= nil then
        messenger:Error("Error setting autosave option -> ", status)
    end
    status = SetLocalOption("statusline", "false", treeView)
    if status ~= nil then
        messenger:Error("Error setting statusline option -> ", status)
    end
    -- TODO: need to set readonly in view type.
    tabs[curTab + 1]:Resize()
end

-- CloseTree will close the tree plugin view and release memory.
function CloseTree()
    debugInfo("Function --> CloseTree()")
    if treeView ~= nil then
        treeView.Buf.IsModified = false
        treeView:Quit(false)
        treeView = nil
    end
end

-- refreshTree will remove the buffer and load contents from folder
function refreshTree()
    debugInfo("Function --> refreshTree()")
    treeView.Buf:remove(treeView.Buf:Start(), treeView.Buf:End())
    local list = table.concat(scanDir(cwd), "\n ")
    if debug == true then
        messenger:AddLog("dir -> ", list)
    end
    treeView.Buf:Insert(Loc(0, 0), list)
end

-- returns currently selected line in treeView
function getSelection()
    debugInfo("Function --> getSelection()")
    debugInfo("** cursor line number --> " .. treeView.Cursor.Loc.Y)
    debugInfo("** selection passed --> " .. treeView.Buf:Line(treeView.Cursor.Loc.Y):sub(2))
    return (treeView.Buf:Line(treeView.Cursor.Loc.Y)):sub(2)
end

-- don't use built-in view.Cursor:SelectLine() as it will copy to clipboard (in old versions of Micro)
-- TODO: We require micro >= 1.3.2, so is this still an issue?
function highlightLineInTree(view)
    if view == treeView then
        debugInfo("Function --> highlightLineInTree(view)")
        local y = view.Cursor.Loc.Y
        view.Cursor.CurSelection[1] = Loc(0, y)
        view.Cursor.CurSelection[2] = Loc(view.Width, y)
    end
end

-- 'beautiful' file selection:
function onCursorDown(view)
    if view == treeView then
        debugInfo("Function --> onCursorDown(view)")
        highlightLineInTree(view)
    end
end
function onCursorUp(view)
    if view == treeView then
        debugInfo("Function --> onCursorUp(view)")
        highlightLineInTree(view)
    end
end

-- mouse callback from micro editor when a left button is clicked on your view
function preMousePress(view, event)
    if view == treeView then -- check view is tree as only want inputs from that view.
        debugInfo("Function --> preMousePress(view, event)")
        local columns, rows = event:Position()
        debugInfo ("** Mouse pressed -> columns = " .. columns .. " rows = "  .. rows)
        return true
    end
end
function onMousePress(view, event)
    if view == treeView then
        debugInfo("Function --> onMousePress(view, event)")
        selectLineInTree(view)
        preInsertNewline(view)
        return false
    end
end

-- disallow selecting topmost line in treeView:
function preCursorUp(view)
    if view == treeView then
        debugInfo("Function --> preCursor(view)")
        if view.Cursor.Loc.Y == 1 then
            return false
        end
    end
end

-- allows for deleting files
function preDelete(view)
    if view == treeView then
        debugInfo("Function --> preDelete(view)")
        local selected = getSelection()
        if selected == ".." then
            return false
        end
        local type, command
        if isDir(selected) then
            type = "dir"
            command = isWin and "del /S /Q" or "rm -r"
        else
            type = "file"
            command = isWin and "del" or "rm -I"
        end
        command = command .. " " .. (isWin and driveLetter or "") .. JoinPaths(cwd, selected)

        local yes, cancel = messenger:YesNoPrompt("Do you want to delete " .. type .. " '" .. selected .. "'? ")
        if not cancel and yes then
            os.execute(command)
            refreshTree()
        end
        -- Clears messenger:
        messenger:Reset()
        messenger:Clear()
        return false -- don't "allow" delete
    end
end

-- When user presses enter then if it is a folder clear buffer and reload contents with folder selected.
-- If it is a file then open it in a new vertical view
function preInsertNewline(view)
    if view == treeView then
        debugInfo("Function --> preInsertNewLine(view)")
        local selected = getSelection()
        if view.Cursor.Loc.Y == 0 then
            return false -- topmost line is cwd, so disallowing selecting it
        elseif isDir(selected) then -- if directory then reload contents of tree view
            debugInfo("** current working directory -> " .. cwd)
            cwd = JoinPaths(cwd, selected)
            debugInfo("** current working directory with selected directory -> " .. cwd)
            refreshTree()
        else -- open file in new vertical view
            local filename = JoinPaths(cwd, selected)
            if isWin then
                filename = driveLetter .. filename
            end
            CurView():VSplitIndex(NewBuffer("", filename), 1)
            CurView():ReOpen()
            tabs[curTab + 1]:Resize()
        end
        return false
    end
    return true
end

-- don't prompt to save tree view
function preQuit(view)
    debugInfo("Function --> preQuit(view)")
    if view == treeView then
        debugInfo("** treeView inner if called")
        view.Buf.IsModified = false
        treeView = nil
    end
end
function preQuitAll(view)
    treeView.Buf.IsModified = false
end

-- scanDir will scan contents of the directory passed.
function scanDir(directory)
    debugInfo("Function --> scanDir( " .. directory .. " )")
    -- setup variables
    local ioutil = import("io/ioutil")
    local list = {}
    local err
    files, err = ioutil.ReadDir(".")
    -- new bindings added to micro V1.3.2
    if err ~= nil then
        messenger:Error("Error reading directory in filemanager plugin.")
    else
        list[1] = (isWin and driveLetter or "") .. cwd -- current directory working.
        list[2] = ".." -- used for going up a level in directory.
        local i = 3 -- start at 3 due to above inserted in list
        for i = 3, #files do
            if files[i]:IsDir() then
                list[i] = files[i]:Name() .. "/" -- add / to directorys
            else
                list[i] = files[i]:Name()
            end
        end
    end

    return list
end

 -- TODO: needs sorting below as not working
function isDir(path)
    debugInfo("Function --> isDir( " .. path .. " )")
    local fullpath = JoinPaths(cwd, path)
    isdir = true
    return isdir
end

-- micro editor commands
MakeCommand("tree", "filemanager.ToggleTree", 0)
AddRuntimeFile("filemanager", "syntax", "syntax.yaml")

-- Lua Notes
-- .. means concat a string (+ in go)
-- # means length of array (eg #files)

-- PROJECT TODO's
-- TODO: Add flag for hidden files and directory showing
-- TODO: Look at icons for fonts for the know file types.
-- TODO: Get readOnly working on the view.
-- TODO: Look at colour theme for directory.

