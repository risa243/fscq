#!/usr/bin/env python3

import json
import sys
import os

(_, fn) = sys.argv

## Coq can produce very deep JSON data structures..
sys.setrecursionlimit(10000)

## XXX hack for now
import_prefix = 'codegen/'

remap = {
  'Cache': {
    'eviction_init':   'var Coq_eviction_init   CoqT = nil',
    'eviction_update': 'var Coq_eviction_update CoqT = nil',
    'eviction_choose': 'var Coq_eviction_choose CoqT = nil',
  },

  'FS': {
    'cachesize': 'var Coq_cachesize CoqT = nil',
  },
}

this_pkgname = None

with open(fn) as f:
  s = f.read()
  d = json.loads(s)

def coqname_in_mod(s):
  return 'Coq_' + s.replace("'", "_prime").replace(".", "_")

def coqname(s):
  global this_pkgname
  if '.' in s:
    (mod, rest) = s.split('.', 1)
    if mod == this_pkgname:
      return coqname_in_mod(rest)
    else:
      return '%s.%s' % (mod, coqname_in_mod(rest))
  else:
    return coqname_in_mod(s)

varname_ctr = 0
def varname():
  global varname_ctr
  varname_ctr += 1
  return "__v_%d" % varname_ctr

def gen_fix_expr(names, lambdas):
  s = []
  s.append('func (__fixarg CoqT) CoqT {')

  for name in names:
    s.append('  var %s CoqT' % coqname(name))

  for (name, lambd) in zip(names, lambdas):
    lvar = gen_expr_assign(lambd, s)
    s.append('  %s = %s' % (coqname(name), lvar))

  s.append('  return CoqApply(%s, __fixarg)' % coqname(names[-1]))
  s.append('}')
  return '\n'.join(s)

def gen_expr_assign(e, s):
  r = gen_expr_assign_real(e, s)
  if len(r) < 1000:
    return r
  else:
    v = varname()
    s.append('  var %s CoqT = %s' % (v, r))
    return v

def gen_expr_assign_real(e, s):
  if e['what'] == 'expr:lambda':
    res = []

    first = True
    for argname in e['argnames']:
      if first:
        res.append('func (%s CoqT) CoqT {' % coqname(argname))
      else:
        res.append('return func (%s CoqT) CoqT {' % coqname(argname))
      first = False

    if first:
      ## This is a lambda but there are no arguments..  They were
      ## probably [Prop]s that got eliminated at extraction time.
      retvar = gen_expr_assign(e['body'], s)
      return retvar
    else:
      retvar = gen_expr_assign(e['body'], res)
      res.append('return %s' % retvar)

    for argname in e['argnames']:
      res.append('}')

    return '\n'.join(res)

  elif e['what'] == 'expr:fix':
    fixnames = [x['name'] for x in e['funcs']]
    fixlambdas = [x['body'] for x in e['funcs']]
    return gen_fix_expr(fixnames, fixlambdas)

  elif e['what'] == 'expr:case':
    resvar = varname()
    s.append('var %s CoqT' % resvar)

    switchvar = gen_expr_assign(e['expr'], s)
    s.append('switch __typesw := (%s).(type) {' % switchvar)

    have_default = False
    for case in e['cases']:
      pat = case['pat']

      if pat['what'] == 'pat:constructor':
        s.append('case *%s:' % coqname(pat['name']))
        for idx, argname in enumerate(pat['argnames']):
          s.append('  var %s CoqT = __typesw.A%d' % (coqname(argname), idx))
          s.append('  var _ = %s' % coqname(argname))
        body = gen_expr_assign(case['body'], s)
        s.append('  %s = %s' % (resvar, body))

      elif pat['what'] == 'pat:wild':
        s.append('default:')
        s.append('  var _ = __typesw')
        body = gen_expr_assign(case['body'], s)
        s.append('  %s = %s' % (resvar, body))
        have_default = True

      elif pat['what'] == 'pat:rel':
        s.append('default:')
        s.append('  var _ = __typesw')
        s.append('  var %s CoqT = %s\n' % (coqname(pat['name']), switchvar))
        body = gen_expr_assign(case['body'], s)
        s.append('  %s = %s' % (resvar, body))
        have_default = True

      else:
        s.append('UNKNOWN PAT %s' % pat['what'])

    if not have_default:
      s.append('default:')
      s.append('  var _ = __typesw')
      s.append('  %s = nil\n' % resvar)
      s.append('  panic("no matching switch type")')

    s.append('}')
    return resvar

  elif e['what'] == 'expr:rel':
    return coqname(e['name'])

  elif e['what'] == 'expr:global':
    return coqname(e['name'])

  elif e['what'] == 'expr:constructor':
    arg_vars = []
    for a in e['args']:
      argvar = gen_expr_assign(a, s)
      arg_vars.append(argvar)

    return '&%s{ %s }' % (coqname(e['name']), ', '.join(arg_vars))

  elif e['what'] == 'expr:exception':
    s.append('panic("%s")' % e['msg'])
    return 'nil'

  elif e['what'] == 'expr:apply':
    funvar = gen_expr_assign(e['func'], s)

    arg_vars = []
    for a in e['args']:
      argvar = gen_expr_assign(a, s)
      arg_vars.append(argvar)

    apply_expr = funvar
    for arg in arg_vars:
      apply_expr = 'CoqApply(%s, %s)' % (apply_expr, arg)

    ## Save the result in a temporary variable, to avoid re-computing
    res = varname()
    s.append('var %s CoqT = %s' % (res, apply_expr))
    return res

  elif e['what'] == 'expr:dummy':
    return 'CoqDummy'

  elif e['what'] == 'expr:let':
    v = gen_expr_assign(e['nameval'], s)
    s.append('var %s CoqT = %s' % (coqname(e['name']), v))
    return gen_expr_assign(e['body'], s)

  elif e['what'] == 'expr:axiom':
    s.append('panic("Axiom not realized")')
    return 'nil'

  elif e['what'] == 'expr:coerce':
    return gen_expr_assign(e['value'], s)

  else:
    s.append('UNKNOWN EXPR %s' % e['what'])
    return 'nil'

def gen_header(d):
  global this_pkgname
  this_pkgname = d['name']

  s = []
  s.append('package %s' % d['name'])
  s.append('import . "gocoq"')
  for modname in d['used_modules']:
    s.append('import "%s%s"' % (import_prefix, modname))
  s.append('var Coq2go_unused bool = true &&')
  for modname in d['used_modules']:
    s.append('  %s.Coq2go_unused &&' % modname)
  s.append('  true')
  s.append('')
  return s

def gen_ind(dec):
  s = []
  for c in dec['constructors']:
    s.append('type %s struct {' % coqname(c['name']))
    for idx, typ in enumerate(c['argtypes']):
      s.append('  A%d CoqT' % idx)
    s.append('}')
  return s

def gen_term(dec):
  if this_pkgname in remap and dec['name'] in remap[this_pkgname]:
    return []

  s = []
  s.append('func () CoqT {')
  v = gen_expr_assign(dec['value'], s)
  s.append('  return %s' % v)
  s.append('} ()')

  return ['var %s CoqT = %s\n' % (coqname(dec['name']), '\n'.join(s))]

def gen_fix(dec):
  ## For a group of N mutually-recursive fixpoints, we generate N
  ## copies of each of the N functions.  This is because Go prohibits
  ## loops during global variable initialization.
  r = []
  names = [x['name'] for x in dec['fixlist']]
  values = [x['value'] for x in dec['fixlist']]
  for i in range(0, len(dec['fixlist'])):
    rot_names = names[i:] + names[:i]
    rot_values = values[i:] + values[:i]
    e = gen_fix_expr(rot_names, rot_values)
    r.append('var %s CoqT = %s' % (coqname(rot_names[-1]), e))
  return r

def print_lines(lines):
  for l in lines:
    print(l)

print_lines(gen_header(d))

for dec in d['declarations']:
  if dec['what'] == 'decl:type':
    pass
  elif dec['what'] == 'decl:term':
    print_lines(gen_term(dec))
  elif dec['what'] == 'decl:fixgroup':
    print_lines(gen_fix(dec))
  elif dec['what'] == 'decl:ind':
    print_lines(gen_ind(dec))
  else:
    assert False, dec

if this_pkgname in remap:
  for (_, defn) in remap[this_pkgname].items():
    print(defn)
