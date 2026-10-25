# generates the TalkType iPhone shortcut: record → backend → clipboard + notification.
import plistlib, sys, uuid
token = sys.argv[1]
if len(sys.argv) < 3:
    sys.exit("usage: make_shortcut.py <token> <endpoint>  e.g. https://talktype.<you>.workers.dev/api/dictate")
endpoint = sys.argv[2]

def txt(s):
    return {"Value": {"string": s, "attachmentsByRange": {}}, "WFSerializationType": "WFTextTokenString"}

def out_ref(uid, name):
    return {"Type": "ActionOutput", "OutputUUID": uid, "OutputName": name}

def attach(uid, name):
    return {"Value": out_ref(uid, name), "WFSerializationType": "WFTextTokenAttachment"}

def txt_with(uid, name):
    return {"Value": {"string": "￼", "attachmentsByRange": {"{0, 1}": out_ref(uid, name)}},
            "WFSerializationType": "WFTextTokenString"}

rec, get = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
actions = [
    {"WFWorkflowActionIdentifier": "is.workflow.actions.recordaudio",
     "WFWorkflowActionParameters": {"UUID": rec, "WFRecordingCompression": "Normal",
                                    "WFRecordingStart": "Immediately", "WFRecordingEnd": "On Tap"}},
    {"WFWorkflowActionIdentifier": "is.workflow.actions.downloadurl",
     "WFWorkflowActionParameters": {
         "UUID": get,
         "WFURL": f"{endpoint}?format=text&app=iPhone",
         "WFHTTPMethod": "POST",
         "WFHTTPBodyType": "File",
         "WFRequestVariable": attach(rec, "Recorded Audio"),
         "ShowHeaders": True,
         "WFHTTPHeaders": {"Value": {"WFDictionaryFieldValueItems": [
             {"WFItemType": 0, "WFKey": txt("Authorization"), "WFValue": txt(f"Bearer {token}")}]},
             "WFSerializationType": "WFDictionaryFieldValue"},
     }},
    {"WFWorkflowActionIdentifier": "is.workflow.actions.setclipboard",
     "WFWorkflowActionParameters": {"WFInput": attach(get, "Contents of URL")}},
    {"WFWorkflowActionIdentifier": "is.workflow.actions.notification",
     "WFWorkflowActionParameters": {"WFNotificationActionTitle": txt("copied, ready to paste"),
                                    "WFNotificationActionBody": txt_with(get, "Contents of URL"),
                                    "WFNotificationActionSound": False}},
]
wf = {
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowClientVersion": "2607.0.2",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowTypes": ["ActionExtension"],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowOutputContentItemClasses": [],
    "WFWorkflowHasOutputFallback": False,
    "WFWorkflowHasShortcutInputVariables": False,
    "WFQuickActionSurfaces": [],
    "WFWorkflowActions": actions,
}
with open("unsigned.shortcut", "wb") as f:
    plistlib.dump(wf, f, fmt=plistlib.FMT_BINARY)
print("ok")
