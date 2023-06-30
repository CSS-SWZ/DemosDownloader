#include <sourcemod>
#include <unixtime_sourcemod>
#include <filenetmessages>

#undef REQUIRE_PLUGIN
#tryinclude <DiscordLog>
#define REQUIRE_PLUGIN

#pragma newdecls required

enum struct Client
{
    int SelectedDateMenu;
    int SelectedHourMenu;
}

enum struct Demo
{
    int Size;
    int Date;
    int DateTime;

    int Minute;
    int Hour;
    int Day;
    int Month;
    int Year;
    
    char Map[40];
    char File[256];
}

// Settings
char BasePath[256];
int DemoLastChangeTime;
int TimeZone;
int RequestDelay;
int DownloadDelay;

Client Clients[MAXPLAYERS + 1];

int RequestCooldown[MAXPLAYERS + 1];

int LastClientDownload;
int DownloadPredictTime;

int DownloadCooldown;

Menu DatesMenu;
Menu HoursMenu;

StringMap Demos;
StringMapSnapshot DemosSnapshot;

#if defined DiscordLog_included
bool Discord;
#endif

/*
.______    __       __    __    _______  __  .__   __.     __  .__   __.  _______   ______   
|   _  \  |  |     |  |  |  |  /  _____||  | |  \ |  |    |  | |  \ |  | |   ____| /  __  \  
|  |_)  | |  |     |  |  |  | |  |  __  |  | |   \|  |    |  | |   \|  | |  |__   |  |  |  | 
|   ___/  |  |     |  |  |  | |  | |_ | |  | |  . `  |    |  | |  . `  | |   __|  |  |  |  | 
|  |      |  `----.|  `--'  | |  |__| | |  | |  |\   |    |  | |  |\   | |  |     |  `--'  | 
| _|      |_______| \______/   \______| |__| |__| \__|    |__| |__| \__| |__|      \______/  
                                                                                             
*/

public Plugin myinfo =
{
    name = "DemosDownloader",
    author = "hEl",
    description = "Allows players to download server demos",
    version = "1.0",
    url = "https://github.com/CSS-SWZ/DemosDownloader"
};

/*
 _______   ______   .______     ____    __    ____  ___      .______       _______       _______.
|   ____| /  __  \  |   _  \    \   \  /  \  /   / /   \     |   _  \     |       \     /       |
|  |__   |  |  |  | |  |_)  |    \   \/    \/   / /  ^  \    |  |_)  |    |  .--.  |   |   (----`
|   __|  |  |  |  | |      /      \            / /  /_\  \   |      /     |  |  |  |    \   \    
|  |     |  `--'  | |  |\  \----.  \    /\    / /  _____  \  |  |\  \----.|  '--'  |.----)   |   
|__|      \______/  | _| `._____|   \__/  \__/ /__/     \__\ | _| `._____||_______/ |_______/    
                                                                                                 
*/

#if defined DiscordLog_included
public void OnLibraryAdded(const char[] name)
{
    if(!strcmp(name, "DiscordLog", false))
        Discord = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if(!strcmp(name, "DiscordLog", false))
        Discord = false;
}
#endif

public void OnPluginStart()
{
    LoadTranslations("demos_downloader.phrases");

    Demos = new StringMap();

    LoadConfig();

    InitDatesMenu();
    InitHoursMenu();
    
    BuildHoursMenu();

    RegConsoleCmd("sm_demos", Command_Demos);
}

public void OnMapStart()
{
    LoadDemos();
    
    BuildDatesMenu();
}

public void OnMapEnd()
{
    Demos.Clear();
    delete DemosSnapshot;
}

/*
.___  ___.      ___       __  .__   __.     _______  __    __  .__   __.   ______ .___________. __    ______   .__   __. 
|   \/   |     /   \     |  | |  \ |  |    |   ____||  |  |  | |  \ |  |  /      ||           ||  |  /  __  \  |  \ |  | 
|  \  /  |    /  ^  \    |  | |   \|  |    |  |__   |  |  |  | |   \|  | |  ,----'`---|  |----`|  | |  |  |  | |   \|  | 
|  |\/|  |   /  /_\  \   |  | |  . `  |    |   __|  |  |  |  | |  . `  | |  |         |  |     |  | |  |  |  | |  . `  | 
|  |  |  |  /  _____  \  |  | |  |\   |    |  |     |  `--'  | |  |\   | |  `----.    |  |     |  | |  `--'  | |  |\   | 
|__|  |__| /__/     \__\ |__| |__| \__|    |__|      \______/  |__| \__|  \______|    |__|     |__|  \______/  |__| \__| 

*/

void DemoDownload(int client, const char[] key)
{
    int time = GetTime();

    if(LastClientDownload)
    {
        int lastClient = GetClientOfUserId(LastClientDownload);

        if(DownloadPredictTime > time && lastClient && lastClient == client)
        {
            PrintToChat(client, "%t", "Download still");
            return;
        }
    }

    if(RequestCooldown[client] > time)
    {
        PrintToChat(client, "%t", "Request cooldown", RequestCooldown[client] - time);
        return;
    }

    if(DownloadCooldown > time)
    {
        PrintToChat(client, "%t", "Download cooldown", DownloadCooldown - time);
        return;
    }

    RequestCooldown[client] = time + RequestDelay;
    Demo demo;

    if(!Demos.GetArray(key, demo, sizeof(demo)))
        return;

    char smPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, smPath, sizeof(smPath), "");

    char path[PLATFORM_MAX_PATH];
    FormatEx(path, sizeof(path), "%s%s", BasePath, demo.File);
    ReplaceString(path, sizeof(path), "{SM_PATH}", smPath, false);

    if(!FileExists(path))
        return;

    if(time - GetFileTime(path, FileTime_LastChange) <= DemoLastChangeTime || !FNM_SendFile(client, path))
    {
        PrintToChat(client, "%t", "Download failure");
        return;
    }

    DownloadCooldown = time + DownloadDelay;
    if(demo.Size == -1)
    {
        PrintToChat(client, "%t", "Download success", demo.File);
    }
    else
    {
        int predictTime = demo.Size / 27000;
        LastClientDownload = GetClientUserId(client);
        DownloadPredictTime = time + predictTime;
        PrintToChat(client, "%t", "Download success time", demo.File, predictTime);
    }

    #if defined DiscordLog_included
    if(Discord)
        DiscordLogClient(client, "Demo download", "%s", demo.File);
    #endif
}

/*
  ______   ______   .___  ___. .___  ___.      ___      .__   __.  _______       _______.
 /      | /  __  \  |   \/   | |   \/   |     /   \     |  \ |  | |       \     /       |
|  ,----'|  |  |  | |  \  /  | |  \  /  |    /  ^  \    |   \|  | |  .--.  |   |   (----`
|  |     |  |  |  | |  |\/|  | |  |\/|  |   /  /_\  \   |  . `  | |  |  |  |    \   \    
|  `----.|  `--'  | |  |  |  | |  |  |  |  /  _____  \  |  |\   | |  '--'  |.----)   |   
 \______| \______/  |__|  |__| |__|  |__| /__/     \__\ |__| \__| |_______/ |_______/    
                                                                                         
*/

public Action Command_Demos(int client, int args)
{
    DatesMenu.Display(client, 0);
    return Plugin_Handled;
}

/*                                                                                       
  ______   ______   .__   __.  _______  __    _______ 
 /      | /  __  \  |  \ |  | |   ____||  |  /  _____|
|  ,----'|  |  |  | |   \|  | |  |__   |  | |  |  __  
|  |     |  |  |  | |  . `  | |   __|  |  | |  | |_ | 
|  `----.|  `--'  | |  |\   | |  |     |  | |  |__| | 
 \______| \______/  |__| \__| |__|     |__|  \______|                

*/

void LoadConfig()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/DemosDownloader.cfg");

    KeyValues kv = new KeyValues("Settings");

    if(!kv.ImportFromFile(path))
        SetFailState("Can`t load config file \"%s\"", path);

    kv.GetString("BasePath", BasePath, sizeof(BasePath));
    TimeZone = kv.GetNum("TimeZone", UT_TIMEZONE_UTC);
    DemoLastChangeTime = kv.GetNum("DemoLastChangeTime", 60);
    RequestDelay = kv.GetNum("RequestDelay", 5);
    DownloadDelay = kv.GetNum("DownloadDelay", 150);

    delete kv;
}

/*
 _______   _______ .___  ___.   ______        _______.
|       \ |   ____||   \/   |  /  __  \      /       |
|  .--.  ||  |__   |  \  /  | |  |  |  |    |   (----`
|  |  |  ||   __|  |  |\/|  | |  |  |  |     \   \    
|  '--'  ||  |____ |  |  |  | |  `--'  | .----)   |   
|_______/ |_______||__|  |__|  \______/  |_______/    
                                                      
*/

void LoadDemos()
{
    char smPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, smPath, sizeof(smPath), "");

    char baseDir[PLATFORM_MAX_PATH];
    strcopy(baseDir, sizeof(baseDir), BasePath);

    ReplaceString(baseDir, sizeof(baseDir), "{SM_PATH}", smPath, false);

    char path[PLATFORM_MAX_PATH];
    strcopy(path, sizeof(path), baseDir);

    if(!DirExists(path))
    {
        LogError("Cant parse directory \"%s\"", path);
        return;
    }

    DirectoryListing directory = OpenDirectory(path);
        
    if(!directory)
    	return;
        
    char buffer[256];
    char buffer2[256];
    FileType type;

    while (directory.GetNext(buffer, sizeof(buffer), type))
    {
        switch(type)
        {
            case FileType_File:
            {
                FormatEx(buffer2, sizeof(buffer2), "%s%s", path, buffer);
                ParseDemo(buffer, sizeof(buffer), FileSize(buffer2));
            }
        }
    }

    DemosSnapshot = Demos.Snapshot();

    delete directory;
}

void ParseDemo(char[] file, int maxlength, int fileSize)
{
    if(!IsValidFile(file))
        return;

    Demo demo;
    strcopy(demo.File, sizeof(demo.File), file);

    ReplaceString(file, maxlength, "auto-", "", false);
    ReplaceString(file, maxlength, ".dem", "", false);

    char buffers[2][32];

    int count = ExplodeString(file, "-", buffers, sizeof(buffers), sizeof(buffers[]));

    if(count != 2)
        return;

    int date = GetDemoDateUnix(buffers[0]);
    int time = GetDemoTimeUnix(buffers[1]);

    demo.DateTime = date + time;
    demo.Date = date;

    int second;
    UnixToTime(demo.DateTime, demo.Year, demo.Month, demo.Day, demo.Hour, demo.Minute, second, TimeZone);

    if(!date)
        return;

    if(!GetDemoMap(file, demo.Map, sizeof(demo.Map)))
        return;

    demo.Size = fileSize;

    char key[32];
    IntToString(demo.DateTime, key, sizeof(key));
    Demos.SetArray(key, demo, sizeof(demo));
}

bool GetDemoMap(const char[] file, char[] buffer, int maxlength)
{
    int pos = 0;
    int symbol = -1;

    for(int i = 0; i < 2; ++i)
    {
        symbol = FindCharInString(file[pos], '-');

        if(symbol == -1)
            return false;

        pos += symbol + 1;
    }

    strcopy(buffer, maxlength, file[pos]);

    return (strlen(buffer) > 0);
}

int GetDemoDateUnix(const char[] buffer)
{
    char date[16];
    strcopy(date, sizeof(date), buffer);
    
    int length = strlen(date);

    if(length != 8)
        return 0;

    int index = length - 2;
    int day = StringToInt(date[index]);
    date[index] = 0;

    index -= 2;
    int month = StringToInt(date[index]);
    date[index] = 0;

    int year = StringToInt(date);

    return TimeToUnix(year, month, day, 0, 0, 0, TimeZone);
}

int GetDemoTimeUnix(const char[] buffer)
{
    char time[16];
    strcopy(time, sizeof(time), buffer);
    
    int length = strlen(time);

    if(length != 6)
        return 0;

    int index = length - 2;
    int seconds = StringToInt(time[index]);
    time[index] = 0;

    index -= 2;
    int minutes = StringToInt(time[index]);
    time[index] = 0;

    int hours = StringToInt(time);

    return TimeToUnix(0, 0, 0, hours, minutes, seconds, TimeZone);
}

/*
.___  ___.  _______ .__   __.  __    __       _______.
|   \/   | |   ____||  \ |  | |  |  |  |     /       |
|  \  /  | |  |__   |   \|  | |  |  |  |    |   (----`
|  |\/|  | |   __|  |  . `  | |  |  |  |     \   \    
|  |  |  | |  |____ |  |\   | |  `--'  | .----)   |   
|__|  |__| |_______||__| \__|  \______/  |_______/    

*/

void InitDatesMenu()
{
    DatesMenu = new Menu(DatesMenu_Handler, MenuAction_Display | MenuAction_Select);
}

void InitHoursMenu()
{
    HoursMenu = new Menu(HoursMenu_Handler, MenuAction_Cancel | MenuAction_Display | MenuAction_Select);
}

void BuildDatesMenu()
{
    if(!Demos.Size)
        return;

    DatesMenu.RemoveAllItems();
    
    ArrayList datesList = new ArrayList(ByteCountToCells(1));

    char key[40];
    char info[40];
    char display[40];
    
    Demo demo;

    for(int i = 0; i < DemosSnapshot.Length; ++i)
    {
        if(!DemosSnapshot.GetKey(i, key, sizeof(key)) || !Demos.GetArray(key, demo, sizeof(demo)))
            continue;

        if(datesList.FindValue(demo.Date) != -1)
            continue;

        datesList.Push(demo.Date);

        FormatEx(display, sizeof(display), "%s%i/%s%i/%i", demo.Day < 10 ? "0":"", demo.Day, demo.Month < 10 ? "0":"", demo.Month, demo.Year);
        IntToString(demo.Date, info, sizeof(info));
        DatesMenu.AddItem(info, display);
    }

    delete datesList;
}

void BuildHoursMenu()
{
    HoursMenu.AddItem("12", "12:00");
    HoursMenu.AddItem("14", "14:00");
    HoursMenu.AddItem("16", "16:00");
    HoursMenu.AddItem("18", "18:00");
    HoursMenu.AddItem("20", "20:00");
    HoursMenu.AddItem("22", "22:00");
    HoursMenu.AddItem("0", "< 12:00");

    HoursMenu.ExitBackButton = true;
}

public int DatesMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
    switch(action)
    {
        case MenuAction_Display:
        {
            char title[256];
            FormatEx(title, sizeof(title), "%T", "DATES_MENU_TITLE", client);
            view_as<Panel>(item).SetTitle(title);
        }
        case MenuAction_Select:
        {
            Clients[client].SelectedDateMenu = item;
            HoursMenu.Display(client, 0);
        }
    }
    return 0;
}

public int HoursMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
    switch(action)
    {
        case MenuAction_Cancel:
        {
            switch(item)
            {
                case MenuCancel_ExitBack: DatesMenu.DisplayAt(client, Clients[client].SelectedDateMenu / 6, 0);
            }
        }
        case MenuAction_Display:
        {
            
            char title[256];
            FormatEx(title, sizeof(title), "%T", "HOURS_MENU_TITLE", client);
            view_as<Panel>(item).SetTitle(title);
        }
        case MenuAction_Select:
        {
            Clients[client].SelectedHourMenu = item;

            DemosMenu(client);
        }
    }
    return 0;
}

void DemosMenu(int client)
{
    SetGlobalTransTarget(client);

    Menu menu = new Menu(DemosMenu_Handler, MenuAction_Cancel | MenuAction_End | MenuAction_Select);
    menu.SetTitle("%t", "DEMOS_MENU_TITLE");
    menu.ExitBackButton = true;

    int selectedDate = GetClientSelectedDate(client);
    int selectedHour = GetClientSelectedHour(client);

    int count = 0;

    Demo demo;
    char display[256];
    char key[40];
    for(int i = 0; i < DemosSnapshot.Length; ++i)
    {
        if(!DemosSnapshot.GetKey(i, key, sizeof(key)) || !Demos.GetArray(key, demo, sizeof(demo)))
            continue;

        if(selectedDate != demo.Date)
            continue;

        if(!selectedHour && demo.Hour >= 12)
            continue;

        if(selectedHour && (selectedHour > demo.Hour || selectedHour + 2 <= demo.Hour))
            continue;

        char size[16];
        if(demo.Size != -1)
            FormatEx(size, sizeof(size), " (%i MB)", demo.Size / 1048576);

        FormatEx(display, sizeof(display), "%s\n%s%i:%s%i", demo.Map, demo.Hour < 10 ? "0":"", demo.Hour, demo.Minute < 10 ? "0":"", demo.Minute);
        StrCat(display, sizeof(display), size);

        menu.AddItem(key, display);
        ++count;
    }

    if(!count)
    {
        FormatEx(display, sizeof(display), "%t", "No demos");
        menu.AddItem("", display, ITEMDRAW_DISABLED);
    }

    menu.Display(client, 0);
}

public int DemosMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
    switch(action)
    {
        case MenuAction_End:
        {
            delete menu;
        }
        case MenuAction_Cancel:
        {
            switch(item)
            {
                case MenuCancel_ExitBack:
                {
                    HoursMenu.DisplayAt(client, Clients[client].SelectedHourMenu / 6, 0);
                }
            }
        }
        case MenuAction_Select:
        {
            char key[40];
            menu.GetItem(item, key, sizeof(key));
            DemoDownload(client, key);
        }
    }
    return 0;
}

/*
 __    __  .___________. __   __          _______.
|  |  |  | |           ||  | |  |        /       |
|  |  |  | `---|  |----`|  | |  |       |   (----`
|  |  |  |     |  |     |  | |  |        \   \    
|  `--'  |     |  |     |  | |  `----.----)   |   
 \______/      |__|     |__| |_______|_______/    
                                                  
*/

int GetClientSelectedDate(int client)
{
    int item = Clients[client].SelectedDateMenu;

    char info[32];
    DatesMenu.GetItem(item, info, sizeof(info));

    return StringToInt(info);
}


int GetClientSelectedHour(int client)
{
    int item = Clients[client].SelectedHourMenu;

    char info[32];
    HoursMenu.GetItem(item, info, sizeof(info));

    return StringToInt(info);
}

bool IsValidFile(const char[] file)
{
    int length = strlen(file);

    if(length < 5)
        return false;

    int i = length;

    while (--i > -1)
    {
    	if (file[i] == '.') 
        {
    		return i > 0 && i + 1 != length && (!strcmp(file[i + 1], "dem", false));
    	}
    }

    return false;
}