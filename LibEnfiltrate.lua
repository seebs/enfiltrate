--[[
    LibEnfiltrate is a generic solution to the question:  There are so many
    of these, how can I look at just the ones I want?

]]--

local filt = {}
filt.filters = {}
Library = Library or {}
Library.LibEnfiltrate = filt

filt.version = "VERSION"
filt.verbose = false

function filt.debug(fmt, ...)
  if filt.verbose then
    filt.printf(fmt, ...)
  end
end

function filt.printf(fmt, ...)
  print(string.format(fmt or 'nil', ...))
end

-- what's a nil to be interpreted as?
filt.defaults = {
  number = 0,
  string = ''
}

--[[
    This is sort of a sketchy attempt at encoding domain-specific
    knowledge about various things one can inspect.
  ]]--
filt.categories = {
  item = {
    tools = {
      color_rarity = {
	trash = 'sellable',
	grey = 'sellable',
	white = 'common',
	green = 'uncommon',
	blue = 'rare',
	purple = 'epic',
	orange = 'relic',
	yellow = 'quest',
      },

      bestpony = { 'sellable', 'common', 'uncommon', 'rare', 'epic', 'relic', 'transcendant', 'quest' },

      item_rarity = function(rarity)
	if type(rarity) == 'number' then
	  return rarity
	end
	-- handle nil, because .rarity isn't set when it's 'common'
	rarity = rarity or 'common'
	-- translate colors because people are lazy
	rarity = filt.categories.item.tools.color_rarity[rarity] or rarity
	for i, v in ipairs(filt.categories.item.tools.bestpony) do
	  if rarity == v then
	    return i
	  end
	end
	return false
      end,

    },

    field_types = {
      stack = 'number',
      maxStack = 'number',
    },

    field_coerce = {
    },

    field_relations = {
      name = 'match',
      rarity = '>=',
    },

    defaults = {
    },

  },
  generic = {
    field_types = {
      stack = 'number',
    },

    field_coerce = {
    },

    field_relations = {
      name = 'match'
    },

    defaults = {
    },
  }
}

-- cleanup that can't happen until the rest is loaded
filt.categories.item.field_coerce.rarity = filt.categories.item.tools.item_rarity


local Filter = {}

Library.LibEnfiltrate.Filter = Filter

-- default to generic type if anyone calls Filter:coerce
Filter.knowledge = filt.categories.generic

Filter.__index = Filter

function Filter:bless(filter)
  setmetatable(filter, self)
end

function Filter:new(name, category, addon)
  category = category or 'generic'
  local o = {
    name = name,
    addon = addon,
    category = category,
    knowledge = filt.categories[category] or filt.categories['generic'],
    includes = { name = 'Includes' },
    excludes = { name = 'Excludes' },
    requires = { name = 'Requires' },
    representation = {
      name = name,
      addon = addon,
      category = category,
      includes = {},
      excludes = {},
      requires = {},
    },
  }
  o.includes.representation = o.representation.includes
  o.excludes.representation = o.representation.excludes
  o.requires.representation = o.representation.requires
  Filter:bless(o)
  return o
end

function Filter:type(newcat)
  local oldcat = self.category
  if newcat then
    self.category = newcat
    self.representation.category = newcat
    self.knowledge = filt.categories[newcat] or filt.categories['generic']
    filt.printf("Set category to '%s'.", newcat)
  end
  return oldcat
end

function Filter:save()
  if self.addon then
    LibEnfiltrateGlobal.filters[self.addon] = LibEnfiltrateGlobal['filters'][self.addon] or {}
    LibEnfiltrateGlobal.filters[self.addon][self.name] = self.representation
  else
    LibEnfiltrateGlobal.filters['LibEnfiltrate'][self.name] = self.representation
  end
end

function Filter:from_representation(representation)
  if type(representation) == 'table' then
    local name = representation.name
    local filter = Filter:new(name, representation.category)
    if representation.includes then
      for _, value in ipairs(representation.includes) do
        filter:include(value)
      end
    end
    if representation.excludes then
      for _, value in ipairs(representation.excludes) do
        filter:exclude(value)
      end
    end
    if representation.requires then
      for _, value in ipairs(representation.requires) do
        filter:require(value)
      end
    end
    return filter
  else
    filt.printf("Can't load non-table representation: type %s.",
      type(representation))
  end
end

function Filter:coerce(field, value)
  local knowledge = self.knowledge
  local coerce_to = knowledge.field_types[field]
  local result = nil
  filt.debug("coerce: self %s, self.category %s, filt %s",
    tostring(self), tostring(self.category), tostring(filt))
  if filt.verbose then
    dump(knowledge)
  end
  if knowledge.field_coerce[field] then
    return knowledge.field_coerce[field](value)
  end
  if not coerce_to then
    if type(value) == 'string' and string.match(value, '^%d+$') then
      coerce_to = 'number'
    else
      coerce_to = 'string'
    end
  end
  if not value then
    result = knowledge.defaults[field] or filt.defaults[coerce_to]
  else
    -- check strings first because we want to smash case
    if coerce_to == 'string' then
      result = string.lower(tostring(value))
    elseif type(value) == coerce_to then
      result = value
    elseif coerce_to == 'number' then
      if type(value) == 'string' then
        if string.match(value, '^%d*%.?%d+$') then
	  result = tonumber(value)
	else
	  filt.printf("Can't convert '%s' to a number.", value)
	end
      else
        filt.printf("Can't coerce %s to a number.", type(value))
      end
    else
      filt.printf("Uh-oh:  Trying to coerce '%s' to '%s'.  Confused.",
        tostring(value),
	tostring(coerce_to))
    end
  end
  return result
end

function Filter:relop(relop, value1, value2)
  if relop == '==' or relop == '=' then
    return value1 == value2
  elseif relop == '~=' or relop == '!=' then
    return value1 ~= value2
  elseif relop == 'match' then
    return string.match(value1, value2)
  else
    -- relationals have extra requirements

    local equal_success = false
    local greater_success = false
    local lessthan_success = false
    if relop == '<=' or relop == '>=' then
      equal_success = true
    end
    if relop == '<=' or relop == '<' then
      lessthan_success = true
    end
    if relop == '>=' or relop == '>' then
      greater_success = true
    end

    if not value1 and not value2 then
      return equal_success
    end
    if not value1 then
      return lessthan_success
    end
    if not value2 then
      return greaterthan_success
    end
    if relop == '<' then
      return value1 < value2
    elseif relop == '<=' then
      return value1 <= value2
    elseif relop == '>=' then
      return value1 >= value2
    elseif relop == '>' then
      return value1 > value2
    else
      filt.printf("Invalid relational operator '%s'", tostring(relop))
      return false
    end
  end
end

function Filter:check_relation(item, relation)
  local item_data = self:coerce(relation.field, item[relation.field])
  local compare_data = self:coerce(relation.field, relation.value)
  local ret = Filter:relop(relation.relation, item_data, compare_data)
  return ret
end

function Filter:match(item)
  for _, test in ipairs(self.excludes) do
    if test(item) then
      return nil
    end
  end
  for _, test in ipairs(self.requires) do
    if not test(item) then
      return nil
    end
  end
  if #self.includes > 0 then
    for _, test in ipairs(self.includes) do
      if test(item) then
        return true
      end
    end
  else
    return true
  end
end

function Filter:filter(table)
  retval = {}
  for key, value in pairs(table) do
    if self:match(value) then
      retval[key] = value
    end
  end
  return retval
end

function Filter:apply(category, matchable, verbose)
  local knowledge = self.knowledge
  local t = type(matchable)
  if t == 'function' then
    filt.printf("Can't insert raw functions in a filter.")
  elseif t == 'string' then
    local code, err = loadstring("local item = ...; " .. matchable)
    if code then
      table.insert(category, code)
      table.insert(category.representation, matchable)
      if verbose then
        filt.printf("Added %s:", category.name)
        Filter:print_one_matchable(nil, matchable)
      end
      return
    else
      field, colon1, relation, colon2, value = string.match(matchable, '([^:]*)(:?)([^:]*)(:?)(.*)')
      if field then
        if not colon1 or colon1 == '' then
	  value = field
	  field = 'name'
	  relation = 'match'
	elseif not colon2 or colon2 == '' then
	  value = relation
	  relation = knowledge.field_relations[field] or '=='
	end
	value = self:coerce(field, value)
	matchable = { field = field, relation = relation, value = value }
	t = 'table'
      else
        filt.printf("Trying to insert <%s>, got error: %s",
          matchable, err)
        return
      end
    end
  end
  -- moved to a separate place so we can fake this up
  if t == 'table' then
    table.insert(category, function(item) return self:check_relation(item, matchable) end)
    table.insert(category.representation, matchable)
    if verbose then
      filt.printf("Added %s:", category.name)
      Filter:print_one_matchable(nil, matchable)
    end
  else
    filt.printf("Can't insert object of type '%s' in a filter.", t)
  end
end

function Filter:disapply(category, index, verbose)
  if category[index] then
    old = category.representation[index] or '<missing representation>'
    table.remove(category, index)
    table.remove(category.representation, index)
    if verbose then
      filt.printf("Removed %s:", category.name)
      self:print_one_matchable(nil, old)
    end
  else
    filt.printf("No index %s to remove.", tostring(index))
  end
end

function Filter:disinclude(index, verbose)
  self:disapply(self.includes, index, verbose)
end

function Filter:disexclude(index, verbose)
  self:disapply(self.excludes, index, verbose)
end

function Filter:disrequire(index, verbose)
  self:disapply(self.requires, index, verbose)
end

function Filter:include(matchable, verbose)
  self:apply(self.includes, matchable, verbose)
end

function Filter:exclude(matchable, verbose)
  self:apply(self.excludes, matchable, verbose)
end

function Filter:require(matchable, verbose)
  self:apply(self.requires, matchable, verbose)
end

function Filter:print_one_matchable(index, matcher)
  local t = type(matcher)
  local spaces = '    '
  local display_idx = ''
  local display_matcher = ''
  if index then
    display_idx = string.format("%d: ", index)
  end
  if t == 'table' then
    display_matcher = string.format('%s %s %s',
      matcher['field'] or '<no field>',
      matcher['relation'] or '<no relation>',
      matcher['value'] or '<no value>')
  elseif t == 'string' then
    display_matcher = string.format('"%s"', matcher)
  else
    display_matcher = string.format('<unknown %s>', t)
  end
  filt.printf("%s%s%s", spaces, display_idx, display_matcher)
end

function Filter:prettyprint(category)
  filt.printf("  %s:", category.name)
  for idx, matcher in ipairs(category.representation) do
    self:print_one_matchable(idx, matcher)
  end
end

function Filter:dump()
  printed_anything = false
  filt.printf("%s [%s]", self.name, self.category or '<no category>')
  if #self.includes > 0 then
    self:prettyprint(self.includes)
    printed_anything = true
  end
  if #self.excludes > 0 then
    self:prettyprint(self.excludes)
    printed_anything = true
  end
  if #self.requires > 0 then
    self:prettyprint(self.requires)
    printed_anything = true
  end
  if not printed_anything then
    filt.printf('  (Empty filter)')
  end
end

function Filter:delete()
  if self.addon then
    LibEnfiltrateGlobal.filters[self.addon][self.name] = nil
  else
    filt.filters[self.name] = nil
    LibEnfiltrateGlobal.filters['LibEnfiltrate'][self.name] = nil
  end
  filt.printf("Removed %s from filters.", self.name)
end

function Filter:load(name, addon)
  addon = addon or 'LibEnfiltrate'
  if LibEnfiltrateGlobal.filters[addon] and LibEnfiltrateGlobal.filters[addon][name] then
    return Filter:from_representation(LibEnfiltrateGlobal.filters[addon][name])
  else
    return nil
  end
end

-- user interface and variable management
function filt.variables_loaded(name)
  if name == 'LibEnfiltrate' then
    LibEnfiltrateGlobal = LibEnfiltrateGlobal or {}
    LibEnfiltrateAccount = LibEnfiltrateAccount or {}
    LibEnfiltrateGlobal.filters = LibEnfiltrateGlobal.filters or {}
    LibEnfiltrateGlobal.filters['LibEnfiltrate'] = LibEnfiltrateGlobal.filters['LibEnfiltrate'] or {}
    for name, filter in pairs(LibEnfiltrateGlobal.filters['LibEnfiltrate']) do
      filt.filters[name] = Filter:from_representation(filter)
    end
  end
end

function filt.slashfilter(args)
  local filter = nil
  local temporary = false
  local addon = nil
  if not args then
    filt.printf("Usage error.")
    return
  end
  if args.v then
    filt.printf("version %s", filt.version)
    return
  end
  if args.a then
    addon = args.a
  end
  if args.f then
    if addon then
      if LibEnfiltrateGlobal.filters[addon][args.f] then
        filter = Filter:from_representation(LibEnfiltrateGlobal.filters[addon][args.f])
      end
    else
      if filt.filters[args.f] then
        filter = filt.filters[args.f]
      end
    end
    if not filter then
      filter = Filter:new(args.f, args.c)
      filt.filters[args.f] = filter
    end
    if args.c then
      filter:type(args.c)
    end
  else
    filter = Filter:new('temp', args.c)
    temporary = true
  end
  if filter then
    local changed = false
    if args.i then
      for _, value in ipairs(args.i) do
        filter:include(value, true)
	changed = true
      end
    end
    if args.leftover_args then
      for _, value in ipairs(args.leftover_args) do
        filter:include(value, true)
	changed = true
      end
    end
    if args.r then
      for _, value in ipairs(args.r) do
        filter:require(value, true)
	changed = true
      end
    end
    if args.x then
      for _, value in ipairs(args.x) do
        filter:exclude(value, true)
	changed = true
      end
    end
    if args.I then
      filter:disinclude(args.I, true)
      changed = true
    end
    if args.X then
      filter:disexclude(args.X, true)
      changed = true
    end
    if args.R then
      filter:disexclude(args.R, true)
      changed = true
    end
    if changed and not temporary then
      filt.printf("Saving changes.")
      filter:save()
    end
  end
  if args.D then
    if filter then
      filter:delete()
    else
      filt.printf("You must specify a filter to delete.")
    end
  end
  if args.d then
    if filter and not temporary then
      filter:dump()
    else
      filt.printf("All defined filters:")
      for name, filter in pairs(filt.filters) do
        filter:dump()
      end
    end
  end
  if args.z then
    items = Inspect.Item.Detail(Utility.Item.Slot.Inventory())
    if filter then
      returns = filter:filter(items)
      itemcount = 0
      returncount = 0
      for _, _ in pairs(items) do
        itemcount = itemcount + 1
      end
      for _, _ in pairs(returns) do
        returncount = returncount + 1
      end
      filt.printf("%d items, %d returns", itemcount, returncount)
      for slot, item in pairs(items) do
	if returns[slot] then
          filt.printf("  %s: %s %s", slot, item.stack or '--', item.name or '--')
	else
          -- filt.printf("  %s: %s %s", slot, item.stack or '--', item.name or '--')
	end
      end
    else
      filt.printf("no filter")
    end
  end
end

table.insert(Event.Addon.SavedVariables.Load.End, { filt.variables_loaded, "LibEnfiltrate", "variable loaded hook" })
Library.LibGetOpt.makeslash("a:c:dDf:i:+I#r:+R#vx:+X#z", "LibEnfiltrate", "enfilt", filt.slashfilter)