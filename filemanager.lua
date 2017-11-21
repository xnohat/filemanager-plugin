VERSION = "2.1.0"

-- check for plugin flags and if not set, set them to default values.
if GetOption("fileManagerPluginShowHiddenFiles") == nil then
    AddOption("fileManagerPluginShowHiddenFiles", true)
end

-- Global variables
treeView = nil
cwd = WorkingDirectory() -- Current working Directory
isWin = (OS == "windows")
debugMode = true -- set to true for debug info or false to disable debug info
showHiddenFiles = true -- show hidden files flag default is to show them.

-- Functions
-- debugInfo is used for logging to micro editor log for debugging plugin.
function debugInfo(log)
    if debugMode == true then
        messenger:AddLog("File manager plugin : " .. log)
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

-- setupOptions setup's tree view options
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
    -- TODO: need to set read only in view type.
    tabs[curTab + 1]:Resize()
    if not GetOption("fileManagerPluginShowHiddenFiles") then
        showHiddenFiles = false
    end
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

-- getSelection returns currently selected line in treeView
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

-- onCursorDown callback from micro editor. Used to highlight line when cursor down is pressed.
function onCursorDown(view)
    if view == treeView then
        debugInfo("Function --> onCursorDown(view)")
        highlightLineInTree(view)
    end
end

-- onCursorUp callback from micro editor. Used to highlight line when cursor up is pressed.
function onCursorUp(view)
    if view == treeView then
        debugInfo("Function --> onCursorUp(view)")
        highlightLineInTree(view)
    end
end

-- onMousePress callback from micro editor. When a left button is clicked on your view.
function preMousePress(view, event)
    if view == treeView then -- check view is tree as only want inputs from that view.
        debugInfo("Function --> preMousePress(view, event)")
        local columns, rows = event:Position()
        debugInfo("** Mouse pressed -> columns = " .. columns .. " rows = " .. rows)
        return true
    end
end

--onMousePress callback from micro editor.
function onMousePress(view, event)
    if view == treeView then
        debugInfo("Function --> onMousePress(view, event)")
        highlightLineInTree(view)
        preInsertNewline(view)
        return false
    end
end

-- preCursorUp callback from micro editor. Disallow selecting topmost line in treeView:
function preCursorUp(view)
    if view == treeView then
        debugInfo("Function --> preCursor(view)")
        if view.Cursor.Loc.Y == 1 then
            return false
        end
    end
end

-- preDelete callback from micro editor. Allows for deleting files
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
        command = command .. " " .. JoinPaths(cwd, selected)

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


-- preInterNewline callback from micro editor. When user presses enter then if it is a folder clear buffer 
-- and reload contents with folder selected or if it is a file then open it in a new vertical view.
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
            CurView():VSplitIndex(NewBuffer("", filename), 1)
            CurView():ReOpen()
            tabs[curTab + 1]:Resize()
        end
        return false
    end
    return true
end

-- preQuit callback from micro editor. Don't prompt to save tree view when it is closed.
function preQuit(view)
    debugInfo("Function --> preQuit(view)")
    if view == treeView then
        debugInfo("** treeView inner if called")
        view.Buf.IsModified = false
        treeView = nil
    end
end

-- TODO: check this callback to see if it is called when all is 
-- preQuitAll callback from micro editor. Don't prompt to save when micro is closed.
function preQuitAll(view)
    treeView.Buf.IsModified = false
end

-- scanDir will scan contents of the directory passed.
function scanDir(directory)
    debugInfo("Function --> scanDir( " .. directory .. " )")
    -- setup variables
    --local cwdFiles = {} -- list of current working directory files and directory's
    local go_ioutil = import("io/ioutil")
    local list = {}
    --local err, i
    local i
    local cwdFiles, err = go_ioutil.ReadDir(directory)
    -- new bindings added to micro V1.3.2
    if err ~= nil then
        messenger:Error("Error reading directory in filemanager plugin.")
    else
        list[1] = cwd -- current directory working.
        list[2] = ".." -- used for going up a level in directory.
        for i = 1, #cwdFiles do
            if cwdFiles[i]:IsDir() then
                list[i + 2] = cwdFiles[i]:Name() .. "/" -- add / to directory's
            else
                list[i + 2] = cwdFiles[i]:Name()
            end
        end
    end
    return list
end

-- TODO: needs sorting below as not working
-- isDir checks the path passed and returns true or false if directory. Returns nil if fails to read path.
function isDir(path)
    -- return true
    if path == ".." then
        return true
    end
    debugInfo("Function --> isDir( " .. path .. " )")
    local fullpath = JoinPaths(cwd, path)
    local go_os = import("os")
    local file_info = go_os.Stat(fullpath) -- Returns a FileInfo on the current file/path

    if file_info ~= nil then
       
        return file_info:IsDir() -- Returns true if directory or false if a file.
    else
        debugInfo("** failed, returning nil ( " .. path .. " )")
        messenger:Error("isDir() failed, returning nil")
        return nil  -- Returns nill if error reading file_info
    end
end

function checkExtension(extension)
    local extensions = {
        styl = "",
        sass = "",
        scss = "",
        htm = "",
        html = "",
        slim = "",
        ejs = "",
        css = "",
        less = "",
        md = "",
        markdown = "",
        rmd = "",
        json = "",
        js = "",
        jsx = "",
        rb = "",
        php = "",
        py = "",
        pyc = "",
        pyo = "",
        pyd = "",
        coffee = "",
        mustache = "",
        hbs = "",
        conf = "",
        ini = "",
        yml = "",
        yaml = "",
        bat = "",
        jpg = "",
        jpeg = "",
        bmp = "",
        png = "",
        gif = "",
        ico = "",
        twig = "",
        cpp = "",
        c = "",
        cxx = "",
        cc = "",
        cp = "",
        c = "",
        h = "",
        hpp = "",
        hxx = "",
        hs = "",
        lhs = "",
        lua = "",
        java = "",
        sh = "",
        fish = "",
        bash = "",
        zsh = "",
        ksh = "",
        csh = "",
        awk = "",
        ps1 = "",
        ml = "λ",
        mli = "λ",
        diff = "",
        db = "",
        sql = "",
        dump = "",
        clj = "",
        cljc = "",
        cljs = "",
        edn = "",
        scala = "",
        go = "",
        dart = "",
        xul = "",
        sln = "",
        suo = "",
        pl = "",
        pm = "",
        t = "",
        rss = "",
        f = "",
        fsscript = "",
        fsx = "",
        fs = "",
        fsi = "",
        rs = "",
        rlib = "",
        d = "",
        erl = "",
        hrl = "",
        vim = "",
        ai = "",
        psd = "",
        psb = "",
        ts = "",
        tsx = "",
        jl = "",
        pp = ""
    }
end
-- micro editor commands
MakeCommand("tree", "filemanager.ToggleTree", 0)
AddRuntimeFile("filemanager", "syntax", "syntax.yaml")

-- Lua Notes
-- .. means concat a string (+ in go)
-- # means length of array (eg #files)

-- PROJECT To do's
-- TODO: Add flag for hidden files and directory showing
-- TODO: Look at icons for fonts for the known file types.
-- TODO: Get readOnly working on the view.
-- TODO: Look at colour theme for directory.
-- TODO: sort delete function out.
