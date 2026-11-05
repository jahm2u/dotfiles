#!/usr/bin/env python3
"""Build the "Traduzir" iPhone shortcut from the translation prompt in config/hammerspoon/init.lua.

The prompt, system message, model, temperature and the language-detection stopwords are
extracted from init.lua (the artifact the Mac runs), so the phone translates exactly like
⌥D. Re-run after changing the prompt; Shortcuts asks whether to replace the old copy.

From the Share sheet (someone else's text) it opens the translation in Quick Look and leaves the
clipboard alone. Run as a button (Back Tap) it translates the clipboard, or asks for text when the
clipboard is empty, and puts the result on the clipboard with a banner.

    scripts/build-translate-shortcut.py           # writes, signs and opens it for import
    scripts/build-translate-shortcut.py --no-open # writes and signs only

The signed file embeds OPENAI_API_KEY, so it lands in $TMPDIR and is deleted after import.
"""
import argparse, importlib.util, os, plistlib, re, subprocess, sys, time, uuid

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT = os.path.join(REPO, "config", "hammerspoon", "init.lua")
NAME = "Traduzir"

spec = importlib.util.spec_from_file_location("replay", os.path.join(REPO, "scripts", "replay-translations.py"))
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)

OBJ = "￼"


def uid():
    return str(uuid.uuid4()).upper()


def out(action_uuid, name):
    return {"OutputUUID": action_uuid, "Type": "ActionOutput", "OutputName": name}


def var(name):
    return {"VariableName": name, "Type": "Variable"}


def attach(token, coerce=None):
    if coerce:
        token = dict(token, Aggrandizements=[{"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": coerce}])
    return {"Value": token, "WFSerializationType": "WFTextTokenAttachment"}


def tstr(*parts):
    """Token string; attachment ranges are NSRange offsets, i.e. UTF-16 code units."""
    s, ranges = "", {}
    for p in parts:
        if isinstance(p, str):
            s += p
        else:
            ranges["{%d, 1}" % (len(s.encode("utf-16-le")) // 2)] = p
            s += OBJ
    value = {"string": s}
    if ranges:
        value["attachmentsByRange"] = ranges
    return {"Value": value, "WFSerializationType": "WFTextTokenString"}


def dict_field(items):
    rows = []
    for key, kind, value in items:
        rows.append({"WFKey": tstr(key), "WFItemType": kind, "WFValue": value})
    return {"Value": {"WFDictionaryFieldValueItems": rows}, "WFSerializationType": "WFDictionaryFieldValue"}


class Builder:
    def __init__(self):
        self.actions = []

    def add(self, ident, **params):
        params.setdefault("UUID", uid())
        self.actions.append({"WFWorkflowActionIdentifier": "is.workflow.actions." + ident,
                             "WFWorkflowActionParameters": params})
        return params["UUID"]

    def text(self, *parts):
        return self.add("gettext", WFTextActionText=tstr(*parts))

    def setvar(self, name, token):
        self.add("setvariable", WFVariableName=name, WFInput=attach(token))

    def if_(self, token, condition, coerce=None, **operand):
        group = uid()
        self.add("conditional", GroupingIdentifier=group, WFControlFlowMode=0, WFCondition=condition,
                 WFInput={"Type": "Variable", "Variable": attach(token, coerce)}, **operand)
        return group

    def else_(self, group):
        self.add("conditional", GroupingIdentifier=group, WFControlFlowMode=1)

    def end(self, group):
        self.add("conditional", GroupingIdentifier=group, WFControlFlowMode=2)


# WFCondition codes, as stored by Shortcuts itself (read from this Mac's library)
LESS, GREATER, GREATER_EQ, EQUALS, HAS_VALUE = 0, 2, 3, 4, 100
NUMBER = "WFNumberContentItem"


def stopword_regex(lua, table):
    words = re.search(r'for w in \("([^"]+)"\):gmatch\("%%S\+"\) do %s\[w\]' % table, lua).group(1).split()
    # Lua splits on runs of [%w\128-\255]; a letter or digit on either side means a longer word
    return r"(?i)(?<![\p{L}\p{N}])(?:%s)(?![\p{L}\p{N}])" % "|".join(map(re.escape, words))


def build(key, debug=False, url="https://api.openai.com/v1/chat/completions"):
    lua = open(INIT, encoding="utf-8").read()
    cfg = replay.extract(lua)
    if not cfg["dynamic"]:
        sys.exit("init.lua prompt has no directionLine; this generator expects the detector version")
    b = Builder()

    # Share sheet = reading someone else's text; a button run = writing, from the clipboard or typed
    g = b.if_({"Type": "ExtensionInput"}, HAS_VALUE)
    b.setvar("texto", {"Type": "ExtensionInput", "Aggrandizements": [
        {"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": "WFStringContentItem"}]})
    b.setvar("modo", out(b.text("ler"), "Text"))
    b.else_(g)
    clip = b.add("getclipboard")
    g2 = b.if_(out(clip, "Clipboard"), HAS_VALUE)
    b.setvar("texto", out(clip, "Clipboard"))
    b.else_(g2)
    asked = b.add("ask", WFAskActionPrompt="O que traduzir?")
    b.setvar("texto", out(asked, "Provided Input"))
    b.end(g2)
    b.setvar("modo", out(b.text("escrever"), "Text"))
    b.end(g)

    # Direction, ported from detectTranslationTarget in init.lua
    for name, table in (("pt", "PT_STOPWORDS"), ("en", "EN_STOPWORDS")):
        m = b.add("text.match", WFMatchTextPattern=stopword_regex(lua, table), WFMatchTextCaseSensitive=False,
                  text=tstr(var("texto")))
        c = b.add("count", Input=attach(out(m, "Matches")))
        b.setvar(name, out(c, "Count"))
        x4 = b.add("math", WFInput=attach(out(c, "Count"), NUMBER), WFMathOperation="×", WFMathOperand="4")
        b.setvar(name + "4", out(x4, "Calculation Result"))

    t = b.text(replay.direction_line(None))
    b.setvar("direcao", out(t, "Text"))
    for a, other, target in (("pt", "en", "English"), ("en", "pt", "Portuguese")):
        g = b.if_(var(a), GREATER, NUMBER, WFNumberValue=attach(var(other), NUMBER))
        t = b.text(replay.direction_line(target))
        b.setvar("direcao", out(t, "Text"))
        b.end(g)
    # Mixed text (minority >= 3 and majority < 4x minority) goes back to the model's own rule
    g1 = b.if_(var("pt"), GREATER_EQ, NUMBER, WFNumberValue="3")
    g2 = b.if_(var("en"), GREATER_EQ, NUMBER, WFNumberValue="3")
    g3 = b.if_(var("pt"), LESS, NUMBER, WFNumberValue=attach(var("en4"), NUMBER))
    g4 = b.if_(var("en"), LESS, NUMBER, WFNumberValue=attach(var("pt4"), NUMBER))
    t = b.text(replay.direction_line(None))
    b.setvar("direcao", out(t, "Text"))
    for g in (g4, g3, g2, g1):
        b.end(g)

    if debug:
        b.add("output", WFOutput=tstr("pt=", var("pt"), " en=", var("en"), " pt4=", var("pt4"), " en4=", var("en4"),
                                      "\n", var("direcao"), "\n---\n", var("texto")))

    prompt = b.text(cfg["head"], var("direcao"), cfg["mid"], var("texto"), cfg["tail"])
    sysd = b.add("dictionary", WFItems=dict_field([("role", 0, tstr("system")), ("content", 0, tstr(cfg["sysmsg"]))]))
    b.setvar("mensagens", out(sysd, "Dictionary"))
    userd = b.add("dictionary", WFItems=dict_field([("role", 0, tstr("user")),
                                                    ("content", 0, tstr(out(prompt, "Text")))]))
    b.add("appendvariable", WFVariableName="mensagens", WFInput=attach(out(userd, "Dictionary")))

    body = [("model", 0, tstr(cfg["model"])),
            ("messages", 2, {"Value": attach(var("mensagens")), "WFSerializationType": "WFArraySubstitutableParameterState"}),
            ("safety_identifier", 0, tstr("dotfiles-translate-ios"))]
    if cfg["temperature"] is not None:
        # A literal "0.2" is parsed with the device locale, and pt-BR reads it as 2; compute it instead
        n = b.add("number", WFNumberActionNumber=str(round(cfg["temperature"] * 100)))
        temp = b.add("math", WFInput=attach(out(n, "Number")), WFMathOperation="÷", WFMathOperand="100")
        body.append(("temperature", 3, tstr(out(temp, "Calculation Result"))))
    resp = b.add("downloadurl", WFURL=url, WFHTTPMethod="POST",
                 WFHTTPBodyType="JSON", ShowHeaders=True, WFJSONValues=dict_field(body),
                 WFHTTPHeaders=dict_field([("Authorization", 0, tstr("Bearer " + key))]))

    content = b.add("getvalueforkey", WFInput=attach(out(resp, "Contents of URL")),
                    WFDictionaryKey="choices.1.message.content")
    g = b.if_(out(content, "Dictionary Value"), HAS_VALUE)
    # Same cleanup as init.lua: drop <text> tags the model sometimes echoes back
    clean = b.add("text.replace", WFInput=tstr(out(content, "Dictionary Value")),
                  WFReplaceTextFind=r"^\s*<text>\s*|\s*</text>\s*$", WFReplaceTextReplace="",
                  WFReplaceTextRegularExpression=True)
    gm = b.if_(var("modo"), EQUALS, WFConditionalActionString="ler")
    # Full text to read; the clipboard is left alone, and Quick Look's share button can still copy it
    b.add("previewdocument", WFInput=attach(out(clean, "Updated Text")))
    b.else_(gm)
    b.add("setclipboard", WFInput=attach(out(clean, "Updated Text")))
    b.add("notification", WFNotificationActionTitle="Copiado", WFNotificationActionSound=False,
          WFNotificationActionBody=tstr(out(clean, "Updated Text")))
    b.end(gm)
    b.else_(g)
    err = b.add("getvalueforkey", WFInput=attach(out(resp, "Contents of URL")), WFDictionaryKey="error.message")
    b.add("notification", WFNotificationActionTitle="Tradução falhou",
          WFNotificationActionBody=tstr(out(err, "Dictionary Value")))
    b.end(g)

    return {
        "WFWorkflowActions": b.actions,
        "WFWorkflowClientVersion": "3607.0.2",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowTypes": ["ActionExtension"],
        "WFWorkflowHasShortcutInputVariables": True,
        "WFQuickActionSurfaces": [],
        "WFWorkflowOutputContentItemClasses": ["WFStringContentItem"] if debug else [],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--debug", action="store_true", help="stop after language detection and output the counts")
    ap.add_argument("--url", default="https://api.openai.com/v1/chat/completions",
                    help="API endpoint; point it at a local server to inspect the request")
    ap.add_argument("--no-open", action="store_true", help="write and sign, but do not open for import")
    args = ap.parse_args()

    workdir = os.path.join(os.environ.get("TMPDIR", "/tmp"), "translate-shortcut")
    os.makedirs(workdir, mode=0o700, exist_ok=True)
    unsigned = os.path.join(workdir, "unsigned.shortcut")
    signed = os.path.join(workdir, NAME + ".shortcut")
    with open(unsigned, "wb") as f:
        plistlib.dump(build(replay.api_key(), args.debug, args.url), f, fmt=plistlib.FMT_BINARY)
    try:
        # Signing goes through Apple's servers and the first call of a session sometimes fails
        for attempt in range(3):
            if subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", unsigned, "--output", signed]).returncode == 0:
                break
            time.sleep(3)
        else:
            sys.exit("shortcuts sign failed 3 times")
    finally:
        os.remove(unsigned)
    print("signed:", signed)
    if args.no_open:
        return
    subprocess.run(["open", signed], check=True)
    # Shortcuts reads the file when the import sheet opens; the key must not linger on disk
    time.sleep(10)
    os.remove(signed)
    print("opened in Shortcuts; click Add Shortcut. File deleted.")


if __name__ == "__main__":
    main()
