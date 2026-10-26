#!/usr/bin/env bash
# Assemble the HAP arm64 library bundle for the in-app Hyprland (route J).
#  - collects libhyprland.so's full runtime closure (incl. the glvnd->mesa GL vendor, which is
#    dlopen'd and so not in NEEDED);
#  - flattens versioned SONAMEs to plain .so (HAP libs must end in .so);
#  - renames every lib whose base name could collide with a HarmonyOS system lib already loaded
#    in the app process (libEGL/libGLESv2/libGLdispatch/libOpenGL/libgbm/libexpat/libinput/
#    libglapi) to an _ohm name, in SONAME + NEEDED + filename, so dlopen binds OUR libs, not the
#    system's (which would silently bind Hyprland to HarmonyOS zink EGL);
#  - strips, writes the glvnd EGL vendor JSON, verifies the closure, reports size.
# Output: $STAGE (default scratchpad/stage3/hap-libs), to be copied into the HAP entry/libs/arm64-v8a.
set -euo pipefail
SP="${SP:?set SP}"; PREFIX="$SP/stage1/prefix"; CXX="$SP/stage3/ohos-cxx-lib"
SO_SRC="${SO_SRC:-/Volumes/ohbuild/work/Hyprland/build/libhyprland.so}"
STAGE="${STAGE:-$SP/stage3/hap-libs}"; rm -rf "$STAGE"; mkdir -p "$STAGE/egl_vendor.d"
cp "$SO_SRC" "$STAGE/"
for v in libEGL_mesa.so.0 libgallium-24.3.4.so libglapi.so.0; do cp "$PREFIX/lib/$v" "$STAGE/"; done
PREFIX="$PREFIX" CXX="$CXX" STAGE="$STAGE" python3 - <<'PY'
import os,subprocess,glob,shutil,collections
stage=os.environ["STAGE"]; dirs=[os.environ["PREFIX"]+"/lib",os.environ["CXX"]]
R="/opt/homebrew/opt/llvm/bin/llvm-readelf";STRIP="/opt/homebrew/opt/llvm/bin/llvm-strip";PE="/opt/homebrew/bin/patchelf"
system={"libc.so","libc++_shared.so","libm.so","libdl.so","libpthread.so","librt.so","ld-musl-aarch64.so.1"}
COLLIDE={"libEGL","libGLESv2","libGLdispatch","libOpenGL","libgbm","libexpat","libinput","libglapi"}
def dyn(f,t):
    o=subprocess.run([R,"-d",f],capture_output=True,text=True).stdout
    return [l.split("[")[1].split("]")[0] for l in o.splitlines() if t in l]
def needed(f): return dyn(f,"NEEDED")
def find(n):
    for d in dirs:
        p=os.path.join(d,n)
        if os.path.exists(p): return os.path.realpath(p)
    for d in dirs:
        g=sorted(glob.glob(os.path.join(d,n)+"*"))
        if g: return os.path.realpath(g[0])
    return None
def finalname(n):
    if n=="libGLESv3.so": n="libGLESv2.so"
    i=n.find(".so"); base=n[:i] if i>=0 else n
    if base in COLLIDE: return base+"_ohm.so"
    return (n[:i+3] if i>=0 else n)
roots=[f for f in os.listdir(stage) if ".so" in f]
q=collections.deque(roots); done=set(); files={f:os.path.join(stage,f) for f in roots}; missing=set()
while q:
    cur=q.popleft()
    if cur in done: continue
    done.add(cur)
    path=files.get(cur) or find(cur)
    if not path:
        if cur not in system: missing.add(cur)
        continue
    for n in needed(path):
        if n in system: continue
        if n not in files:
            s=find(n)
            if not s: missing.add(n); continue
            shutil.copy2(s,os.path.join(stage,os.path.basename(s))); files[n]=os.path.join(stage,os.path.basename(s))
        q.append(n)
assert not missing, ("MISSING "+str(sorted(missing)))
libfiles=[f for f in os.listdir(stage) if ".so" in f]
remap={}
for f in libfiles:
    for n in needed(os.path.join(stage,f))+dyn(os.path.join(stage,f),"SONAME"):
        if finalname(n)!=n: remap[n]=finalname(n)
for f in libfiles:
    p=os.path.join(stage,f); sn=dyn(p,"SONAME")
    subprocess.run([PE,"--set-soname",finalname(sn[0]) if sn else finalname(f),p],capture_output=True)
    for old,new in remap.items(): subprocess.run([PE,"--replace-needed",old,new,p],capture_output=True)
for f in libfiles:
    u=finalname(f)
    if u!=f and os.path.exists(os.path.join(stage,f)): os.replace(os.path.join(stage,f),os.path.join(stage,u))
final=sorted(set(finalname(f) for f in libfiles))
for f in final: subprocess.run([STRIP,os.path.join(stage,f)],capture_output=True)
have=set(final); bad=[f+"->"+n for f in final for n in needed(os.path.join(stage,f)) if n not in have and n not in system]
coll=[f for f in final if f[:f.find(".so")] in COLLIDE]
print("COUNT:",len(final)); print("\n".join(final))
print("UNRESOLVED:", bad or "NONE"); print("STILL-COLLIDING:", coll or "NONE")
print("TOTAL: %.1f MB"%(sum(os.path.getsize(os.path.join(stage,f)) for f in final)/1048576))
PY
# glvnd EGL vendor JSON (library_path resolved at runtime to the HAP libs dir by bbload.cpp;
# this copy is for reference / offline validation)
printf '{\n  "file_format_version":"1.0.0",\n  "ICD":{"library_path":"libEGL_mesa.so"}\n}\n' > "$STAGE/egl_vendor.d/50_mesa.json"
echo "staged to: $STAGE"
