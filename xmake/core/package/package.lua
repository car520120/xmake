--!A cross-platform build utility based on Lua
--
-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific package governing permissions and
-- limitations under the License.
-- 
-- Copyright (C) 2015 - 2019, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        package.lua
--

-- define module
local package   = package or {}
local _instance = _instance or {}

-- load modules
local os             = require("base/os")
local io             = require("base/io")
local path           = require("base/path")
local utils          = require("base/utils")
local table          = require("base/table")
local global         = require("base/global")
local scopeinfo      = require("base/scopeinfo")
local interpreter    = require("base/interpreter")
local sandbox        = require("sandbox/sandbox")
local config         = require("project/config")
local platform       = require("platform/platform")
local language       = require("language/language")
local sandbox        = require("sandbox/sandbox")
local sandbox_os     = require("sandbox/modules/os")
local sandbox_module = require("sandbox/modules/import/core/sandbox/module")

-- new an instance
function _instance.new(name, info, scriptdir)
    local instance = table.inherit(_instance)
    instance._NAME = name
    instance._INFO = info
    instance._SCRIPTDIR = scriptdir
    return instance
end

-- get the package name 
function _instance:name()
    return self._NAME
end

-- get the package configure
function _instance:get(name)

    -- get it from info first
    local value = self._INFO:get(name)
    if value ~= nil then
        return value 
    end
end

-- set the value to the package info
function _instance:set(name, ...)
    self._INFO:apival_set(name, ...)
end

-- add the value to the package info
function _instance:add(name, ...)
    self._INFO:apival_add(name, ...)
end

-- get the extra configuration
function _instance:extraconf(name, item, key)
    return self._INFO:extraconf(name, item, key)
end

-- get the package description
function _instance:description()
    return self:get("description")
end

-- get the platform of package
function _instance:plat()
    -- @note we uses os.host() instead of them for the binary package
    if self:kind() == "binary" then
        return os.host()
    end
    return config.get("plat") or os.host()
end

-- get the architecture of package
function _instance:arch()
    -- @note we uses os.arch() instead of them for the binary package
    if self:kind() == "binary" then
        return os.arch()
    end
    return config.get("arch") or os.arch()
end

-- get the build mode
function _instance:mode()
    return self:debug() and "debug" or "release"
end

-- get the repository of this package
function _instance:repo()
    return self._REPO
end

-- get the package alias  
function _instance:alias()
    local requireinfo = self:requireinfo()
    if requireinfo then
        return requireinfo.alias 
    end
end

-- get urls
function _instance:urls()
    return self._URLS or table.wrap(self:get("urls"))
end

-- get urls
function _instance:urls_set(urls)
    self._URLS = urls
end

-- get the alias of url, @note need raw url
function _instance:url_alias(url)
    local urls_extra = self:get("__extra_urls")
    if urls_extra then
        local urlextra = urls_extra[url]
        if urlextra then
            return urlextra.alias
        end
    end
end

-- get the version filter of url, @note need raw url
function _instance:url_version(url)
    local urls_extra = self:get("__extra_urls")
    if urls_extra then
        local urlextra = urls_extra[url]
        if urlextra then
            return urlextra.version
        end
    end
end

-- get the excludes list of url for the archive extractor, @note need raw url
function _instance:url_excludes(url)
    local urls_extra = self:get("__extra_urls")
    if urls_extra then
        local urlextra = urls_extra[url]
        if urlextra then
            return urlextra.excludes
        end
    end
end

-- get the given dependent package
function _instance:dep(name)
    local deps = self:deps()
    if deps then
        return deps[name]
    end
end

-- get deps
function _instance:deps()
    return self._DEPS
end

-- get order deps
function _instance:orderdeps()
    return self._ORDERDEPS
end

-- add deps
function _instance:deps_add(...)
    for _, dep in ipairs({...}) do
        self:add("deps", dep:name())
        self._DEPS = self._DEPS or {}
        self._DEPS[dep:name()] = dep
        self._ORDERDEPS = self._ORDERDEPS or {}
        table.insert(self._ORDERDEPS, dep)
    end
end

-- get hash of the source package for the url_alias@version_str
function _instance:sourcehash(url_alias)

    -- get sourcehash
    local versions    = self:get("versions")
    local version_str = self:version_str()
    if versions and version_str then

        local sourcehash = nil
        if url_alias then
            sourcehash = versions[url_alias .. ":" ..version_str]
        end
        if not sourcehash then
            sourcehash = versions[version_str]
        end

        -- ok?
        return sourcehash
    end
end

-- get revision(commit, tag, branch) of the url_alias@version_str, only for git url
function _instance:revision(url_alias)
    return self:sourcehash(url_alias)
end

-- get the package kind, binary or nil(static, shared)
function _instance:kind()
    return self:get("kind")
end

-- get the cached directory of this package
function _instance:cachedir()
    local name = self:name():lower():gsub("::", "_")
    return path.join(package.cachedir(), name:sub(1, 1):lower(), name, self:version_str())
end

-- get the installed directory of this package
function _instance:installdir(...)
    local name = self:name():lower():gsub("::", "_")
    local dir = path.join(package.installdir(), name:sub(1, 1):lower(), name, self:version_str(), self:buildhash(), ...)
    if not os.isdir(dir) then
        os.mkdir(dir)
    end
    return dir
end

-- get the script directory
function _instance:scriptdir()
    return self._SCRIPTDIR
end

-- get the references info of this package
function _instance:references()
    local references_file = path.join(self:installdir(), "references.txt")
    if os.isfile(references_file) then
        local references, errors = io.load(references_file)
        if not references then
            os.raise(errors)
        end
        return references
    end
end

-- get the manifest file of this package
function _instance:manifest_file()
    return path.join(self:installdir(), "manifest.txt")
end

-- load the manifest file of this package
function _instance:manifest_load()
    local manifest_file = self:manifest_file()
    if os.isfile(manifest_file) then
        
        -- load manifest
        local manifest, errors = io.load(manifest_file)
        if not manifest then
            os.raise(errors)
        end
        return manifest
    end
end

-- save the manifest file of this package
function _instance:manifest_save()

    -- make manifest
    local manifest       = {}
    manifest.name        = self:name()
    manifest.description = self:description()
    manifest.version     = self:version_str()
    manifest.kind        = self:kind()
    manifest.plat        = self:plat()
    manifest.arch        = self:arch()
    manifest.mode        = self:mode()
    manifest.configs     = self:configs()
    manifest.envs        = self:envs()

    -- save variables
    local vars = {}
    local apis = language.apis()
    for _, apiname in ipairs(table.join(apis.values, apis.pathes)) do
        if apiname:startswith("package.add_") or apiname:startswith("package.set_")  then
            local name = apiname:sub(13)
            local value = self:get(name)
            if value ~= nil then
                vars[name] = value
            end
        end
    end
    manifest.vars = vars

    -- save repository
    local repo = self:repo()
    if repo then
        manifest.repo        = {}
        manifest.repo.name   = repo:name()
        manifest.repo.url    = repo:url()
        manifest.repo.branch = repo:branch()
    end

    -- save manifest
    local ok, errors = io.save(self:manifest_file(), manifest)
    if not ok then
        os.raise(errors)
    end
end

-- TODO: set the given variable, deprecated
function _instance:setvar(name, ...)
    self:set(name, ...)
end

-- TODO add the given variable, deprecated
function _instance:addvar(name, ...)
    self:add(name, ...)
end

-- get the exported environments
function _instance:envs()
    local envs = self._ENVS
    if not envs then
        envs = {}
        if self:kind() == "binary" then
            envs.PATH = {"bin"}
        end
        self._ENVS = envs
    end
    return envs
end

-- enter the package environments
function _instance:envs_enter()

    -- save the old environments
    local oldenvs = self._OLDENVS
    if not oldenvs then
        oldenvs = {}
        self._OLDENVS = oldenvs
    end

    -- add the new environments
    local installdir = self:installdir()
    for name, values in pairs(self:envs()) do
        oldenvs[name] = oldenvs[name] or os.getenv(name)
        if name == "PATH" then
            for _, value in ipairs(values) do
                if path.is_absolute(value) then
                    os.addenv(name, value)
                else
                    os.addenv(name, path.join(installdir, value))
                end
            end
        else
            os.addenv(name, unpack(table.wrap(values)))
        end
    end
end

-- leave the package environments
function _instance:envs_leave()
    if self._OLDENVS then
        for name, values in pairs(self._OLDENVS) do
            os.setenv(name, values)
        end
        self._OLDENVS = nil
    end
end

-- get the given environment variable
function _instance:getenv(name)
    return self:envs()[name]
end

-- set the given environment variable
function _instance:setenv(name, ...)
    self:envs()[name] = {...}
end

-- add the given environment variable
function _instance:addenv(name, ...)
    self:envs()[name] = table.join(self:envs()[name] or {}, ...)
end

-- get user private data
function _instance:data(name)
    return self._DATA and self._DATA[name] or nil
end

-- set user private data
function _instance:data_set(name, data)
    self._DATA = self._DATA or {}
    self._DATA[name] = data
end

-- add user private data
function _instance:data_add(name, data)
    self._DATA = self._DATA or {}
    self._DATA[name] = table.unwrap(table.join(self._DATA[name] or {}, data))
end

-- get the downloaded original file
function _instance:originfile()
    return self._ORIGINFILE
end

-- set the downloaded original file
function _instance:originfile_set(filepath)
    self._ORIGINFILE = filepath
end

-- get versions
function _instance:versions()

    -- make versions 
    if self._VERSIONS == nil then

        -- get versions
        local versions = {}
        for version, _ in pairs(table.wrap(self:get("versions"))) do

            -- remove the url alias prefix if exists
            local pos = version:find(':', 1, true)
            if pos then
                version = version:sub(pos + 1, -1)
            end
            table.insert(versions, version)
        end

        -- remove repeat
        self._VERSIONS = table.unique(versions)
    end
    return self._VERSIONS
end

-- get the version  
function _instance:version()
    return self._VERSION or {}
end

-- get the version string 
function _instance:version_str()
    return self:version().raw or self:version().version
end

-- the verson from tags, branches or versions?
function _instance:version_from(...)

    -- from source?
    for _, source in ipairs({...}) do
        if self:version().source == source then
            return true
        end
    end
end

-- set the version
function _instance:version_set(version, source)

    -- init package version
    if type(version) == "string" then
        version = {version = version, source = source}
    else
        version.source = source
    end

    -- save version
    self._VERSION = version
end

-- get the require info 
function _instance:requireinfo()
    return self._REQUIREINFO 
end

-- set the require info 
function _instance:requireinfo_set(requireinfo)
    self._REQUIREINFO = requireinfo
end

-- get the given configuration value of package
function _instance:config(name)
    local configs = self:configs()
    if configs then
        return configs[name]
    end
end

-- get the configurations of package
function _instance:configs()
    local configs = self._CONFIGS
    if configs == nil then
        local configs_defined = self:get("configs")
        if configs_defined then
            configs = {}
            local requireinfo = self:requireinfo()
            local configs_required = requireinfo and requireinfo.configs or {}
            for _, name in ipairs(table.wrap(configs_defined)) do
                local value = configs_required[name]
                if value == nil then
                    value = self:extraconf("configs", name, "default")
                end
                configs[name] = value
            end
        else
            configs = false
        end
        self._CONFIGS = configs
    end
    return configs and configs or nil
end

-- get the build hash
function _instance:buildhash()
    if self._BUILDHASH == nil then
        local str = self:plat() .. self:arch() 
        local configs = self:configs()
        if configs then
            str = str .. string.serialize(configs, true)
        end
        self._BUILDHASH = hash.uuid(str):gsub('-', ''):lower()
    end
    return self._BUILDHASH
end

-- get the group name
function _instance:group()
    local requireinfo = self:requireinfo()
    if requireinfo then
        return requireinfo.group
    end
end

-- is optional package?
function _instance:optional()
    local requireinfo = self:requireinfo()
    return requireinfo and requireinfo.optional or false
end

-- is debug package?
function _instance:debug()
    return self:config("debug")
end

-- is the supported package?
function _instance:supported()
    -- attempt to get the install script with the current plat/arch
    return self:script("install") ~= nil
end

-- is the third-party package? e.g. brew::pcre2/libpcre2-8, conan::OpenSSL/1.0.2n@conan/stable 
-- we need install and find package by third-party package manager directly
--
function _instance:is3rd()
    return self._is3rd
end

-- is the system package?
function _instance:isSys()
    return self._isSys
end

-- get xxx_script
function _instance:script(name, generic)

    -- get script
    local script = self:get(name)
    local result = nil
    if type(script) == "function" then
        result = script
    elseif type(script) == "table" then

        -- get plat and arch
        local plat = self:plat() or ""
        local arch = self:arch() or ""

        -- match script for special plat and arch
        local pattern = plat .. '|' .. arch
        for _pattern, _script in pairs(script) do
            if not _pattern:startswith("__") and pattern:find('^' .. _pattern .. '$') then
                result = _script
                break
            end
        end

        -- match script for special plat
        if result == nil then
            for _pattern, _script in pairs(script) do
                if not _pattern:startswith("__") and plat:find('^' .. _pattern .. '$') then
                    result = _script
                    break
                end
            end
        end

        -- get generic script
        result = result or script["__generic__"] or generic
    end

    -- only generic script
    result = result or generic

    -- imports some modules first
    if result and result ~= generic then
        local scope = getfenv(result)
        if scope then
            for _, modulename in ipairs(table.wrap(self:get("imports"))) do
                scope[sandbox_module.name(modulename)] = sandbox_module.import(modulename, {anonymous = true})
            end
        end
    end

    -- ok
    return result
end

-- fetch the local package info 
--
-- @param opt   the fetch option, .e.g {force = true, system = false}
--
-- @return {packageinfo}, fetchfrom (.e.g xmake/system)
--
function _instance:fetch(opt)

    -- init options
    opt = opt or {}

    -- attempt to get it from cache
    local fetchinfo = self._FETCHINFO
    if not opt.force and fetchinfo then
        return fetchinfo
    end

    -- fetch the require version
    local require_ver = opt.version or self:requireinfo().version
    if not require_ver:find('.', 1, true) then
        require_ver = nil
    end

    -- nil: find xmake or system packages
    -- true: only find system package
    -- false: only find xmake packages
    local system = opt.system or self:requireinfo().system

    -- fetch binary tool?
    fetchinfo = nil
    local isSys = nil
    if self:kind() == "binary" then
    
        -- import find_tool
        self._find_tool = self._find_tool or sandbox_module.import("lib.detect.find_tool", {anonymous = true})

        -- only fetch it from the xmake repository first
        if not fetchinfo and system ~= true and not self:is3rd() then
            fetchinfo = self._find_tool(self:name(), {version = self:version_str(),
                                                      cachekey = "fetch_package_xmake",
                                                      buildhash = self:buildhash(),
                                                      force = opt.force}) 
            if fetchinfo then
                isSys = self._isSys
            end
        end

        -- fetch it from the system directories
        if not fetchinfo and system ~= false then
            fetchinfo = self._find_tool(self:name(), {cachekey = "fetch_package_system",
                                                      force = opt.force})
            if fetchinfo then
                isSys = true 
            end
        end
    else

        -- import find_package
        self._find_package = self._find_package or sandbox_module.import("lib.detect.find_package", {anonymous = true})

        -- only fetch it from the xmake repository first
        if not fetchinfo and system ~= true and not self:is3rd() then
            fetchinfo = self._find_package("xmake::" .. self:name(), {version = self:version_str(),
                                                                      cachekey = "fetch_package_xmake",
                                                                      buildhash = self:buildhash(),
                                                                      force = opt.force}) 
            if fetchinfo then
                isSys = self._isSys
            end
        end

        -- fetch it from the system directories
        if not fetchinfo and system ~= false then
            fetchinfo = self._find_package(self:name(), {force = opt.force, 
                                                         version = require_ver, 
                                                         mode = self:mode(),
                                                         cachekey = "fetch_package_system",
                                                         system = true})
            if fetchinfo then 
                isSys = true
            end
        end
    end

    -- save to cache
    self._FETCHINFO = fetchinfo
                
    -- mark as system package?
    if isSys ~= nil then
        self._isSys = isSys
    end

    -- ok
    return fetchinfo
end

-- exists this package?
function _instance:exists()
    return self._FETCHINFO ~= nil
end

-- fetch all local info with dependencies
function _instance:fetchdeps()
    local fetchinfo = self:fetch()
    if not fetchinfo then
        return
    end
    local orderdeps = self:orderdeps()
    if orderdeps then
        local total = #orderdeps
        for idx, _ in ipairs(orderdeps) do
            local dep = orderdeps[total + 1 - idx]
            local depinfo = dep:fetch()
            if depinfo then
                for name, values in pairs(depinfo) do
                    fetchinfo[name] = table.wrap(fetchinfo[name])
                    table.join2(fetchinfo[name], values)
                end
            end
        end
    end
    if fetchinfo then
        for name, values in pairs(fetchinfo) do
            fetchinfo[name] = table.unwrap(table.unique(table.wrap(values)))
        end
    end
    return fetchinfo
end

-- get the patches of the current version
function _instance:patches()
    local patches = self._PATCHES
    if patches == nil then
        local patchinfos = self:get("patches")
        if patchinfos then
            local version_str = self:version_str()
            patchinfos = patchinfos[version_str]
            if patchinfos then
                patches = {}
                patchinfos = table.wrap(patchinfos)
                for idx = 1, #patchinfos, 2 do
                    table.insert(patches , {patchinfos[idx], patchinfos[idx + 1]})
                end
            end
        end
        self._PATCHES = patches or false
    end
    return patches and patches or nil
end

-- has the given c funcs?
--
-- @param funcs     the funcs
-- @param opt       the argument options, .e.g { includes = ""}
--
-- @return          true or false
--
function _instance:has_cfuncs(funcs, opt)
    opt = opt or {}
    opt.configs = self:fetchdeps()
    return sandbox_module.import("lib.detect.has_cfuncs", {anonymous = true})(funcs, opt)
end

-- has the given c++ funcs?
--
-- @param funcs     the funcs
-- @param opt       the argument options, .e.g { includes = ""}
--
-- @return          true or false
--
function _instance:has_cxxfuncs(funcs, opt)
    opt = opt or {}
    opt.configs = self:fetchdeps()
    return sandbox_module.import("lib.detect.has_cxxfuncs", {anonymous = true})(funcs, opt)
end

-- the current mode is belong to the given modes?
function package._api_is_mode(interp, ...)
    return config.is_mode(...)
end

-- the current platform is belong to the given platforms?
function package._api_is_plat(interp, ...)
    return config.is_plat(...)
end

-- the current platform is belong to the given architectures?
function package._api_is_arch(interp, ...)
    return config.is_arch(...)
end

-- the current host is belong to the given hosts?
function package._api_is_host(interp, ...)
    return os.is_host(...)
end

-- the interpreter
function package._interpreter()

    -- the interpreter has been initialized? return it directly
    if package._INTERPRETER then
        return package._INTERPRETER
    end

    -- init interpreter
    local interp = interpreter.new()
    assert(interp)
 
    -- define apis
    interp:api_define(package.apis())

    -- define apis for language
    interp:api_define(language.apis())
    
    -- save interpreter
    package._INTERPRETER = interp

    -- ok?
    return interp
end

-- get package apis
function package.apis()

    return 
    {
        values =
        {
            -- package.set_xxx
            "package.set_urls"
        ,   "package.set_kind"
        ,   "package.set_homepage"
        ,   "package.set_description"
            -- package.add_xxx
        ,   "package.add_deps"
        ,   "package.add_urls"
        ,   "package.add_imports"
        ,   "package.add_configs"
        }
    ,   script =
        {
            -- package.on_xxx
            "package.on_load"
        ,   "package.on_install"
        ,   "package.on_test"

            -- package.before_xxx
        ,   "package.before_install"
        ,   "package.before_test"

            -- package.before_xxx
        ,   "package.after_install"
        ,   "package.after_test"
        }
    ,   keyvalues = 
        {
            -- package.add_xxx
            "package.add_patches"
        }
    ,   dictionary = 
        {
            -- package.add_xxx
            "package.add_versions"
        }
    ,   custom = 
        {
            -- is_xxx
            { "is_host", package._api_is_host }
        ,   { "is_mode", package._api_is_mode }
        ,   { "is_plat", package._api_is_plat }
        ,   { "is_arch", package._api_is_arch }
        }
    }
end

-- the cache directory
function package.cachedir()
    return path.join(global.directory(), "cache", "packages")
end

-- the install directory
function package.installdir()
    return path.join(global.directory(), "packages")
end

-- load the package from the system directories
function package.load_from_system(packagename)

    -- get it directly from cache first
    package._PACKAGES = package._PACKAGES or {}
    if package._PACKAGES[packagename] then
        return package._PACKAGES[packagename]
    end

    -- get package info
    local packageinfo = {}
    local is3rd = false
    if packagename:find("::", 1, true) then

        -- get interpreter
        local interp = package._interpreter()

        -- on install script
        local on_install = function (pkg)
            local opt = table.copy(pkg:configs())
            opt.mode = pkg:debug() and "debug" or "release"
            opt.plat = pkg:plat()
            opt.arch = pkg:arch()
            import("package.manager.install_package")(pkg:name(), opt)
        end

        -- make sandbox instance with the given script
        local instance, errors = sandbox.new(on_install, interp:filter())
        if not instance then
            return nil, errors
        end

        -- save the install script
        packageinfo.install = instance:script()

        -- is third-party package?
        if not packagename:startswith("xmake::") then
            is3rd = true
        end
    end

    -- new an instance
    local instance, errors = _instance.new(packagename, scopeinfo.new("package", packageinfo))
    if not instance then
        return nil, errors
    end

    -- mark as system or 3rd package
    instance._isSys = true
    instance._is3rd = is3rd

    -- add configurations for the 3rd package
    if is3rd then
        local install_package = sandbox_module.import("package.manager." .. packagename:split("::")[1]:lower() .. ".install_package", {try = true, anonymous = true})
        if install_package and install_package.configurations then
            for name, conf in pairs(install_package.configurations()) do
                instance:add("configs", name, conf)
            end
        end
    end

    -- save instance to the cache
    package._PACKAGES[packagename] = instance

    -- ok
    return instance
end

-- load the package from the project file
function package.load_from_project(packagename, project)

    -- get it directly from cache first
    package._PACKAGES = package._PACKAGES or {}
    if package._PACKAGES[packagename] then
        return package._PACKAGES[packagename]
    end

    -- load packages (with cache)
    local packages, errors = project.packages()
    if not packages then
        return nil, errors
    end

    -- not found?
    if not packages[packagename] then
        return
    end

    -- new an instance
    local instance, errors = _instance.new(packagename, packages[packagename])
    if not instance then
        return nil, errors
    end

    -- save instance to the cache
    package._PACKAGES[packagename] = instance

    -- ok
    return instance
end

-- load the package from the package directory or package description file
function package.load_from_repository(packagename, repo, packagedir, packagefile)

    -- get it directly from cache first
    package._PACKAGES = package._PACKAGES or {}
    if package._PACKAGES[packagename] then
        return package._PACKAGES[packagename]
    end

    -- load repository first for checking the xmake minimal version
    repo:load()

    -- find the package script path
    local scriptpath = packagefile
    if not packagefile and packagedir then
        scriptpath = path.join(packagedir, "xmake.lua")
    end
    if not scriptpath or not os.isfile(scriptpath) then
        return nil, string.format("the package %s not found!", packagename)
    end

    -- get interpreter
    local interp = package._interpreter()

    -- load script
    local ok, errors = interp:load(scriptpath)
    if not ok then
        return nil, errors
    end

    -- load package and disable filter, we will process filter after a while
    local results, errors = interp:make("package", true, false)
    if not results then
        return nil, errors
    end

    -- get the package info
    local packageinfo = nil
    for name, info in pairs(results) do
        packagename = name -- use the real package name in package() definition
        packageinfo = info
        break
    end

    -- check this package 
    if not packageinfo then
        return nil, string.format("%s: the package %s not found!", scriptpath, packagename)
    end

    -- new an instance
    local instance, errors = _instance.new(packagename, packageinfo, path.directory(scriptpath))
    if not instance then
        return nil, errors
    end

    -- save repository
    instance._REPO = repo

    -- save instance to the cache
    package._PACKAGES[packagename] = instance

    -- ok
    return instance
end
     
-- return module
return package
