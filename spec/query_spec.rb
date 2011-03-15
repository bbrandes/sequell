require 'spec_helper'

describe "SQLQuery" do
  context "given different game types in the query" do
    it "should select the appropriate tables" do
      lg('!lg *').query_tables[0].should eql('logrecord')
      lg('!lm *').query_tables[0].should eql('milestone')
      lg('!lg * crawl').query_tables[0].should eql('logrecord')
      lg('!lm * crawl').query_tables[0].should eql('milestone')
      lg('!lg * sprint').query_tables[0].should eql('spr_logrecord')
      lg('!lg * game=sprint').query_tables[0].should eql('spr_logrecord')
      lg('!lm * sprint').query_tables[0].should eql('spr_milestone')
      lg('!lg * zotdef').query_tables[0].should eql('zot_logrecord')
      lg('!lm * zotdef').query_tables[0].should eql('zot_milestone')
      lg('!lm * game=zotdef').query_tables[0].should eql('zot_milestone')

      lg_error('!lm * !zotdef').should \
          eql("Bad argument `!zotdef`: `zotdef` cannot be negated")
      lg_error('!lm * game=cow').should \
          eql("Bad game type `cow`: known types are crawl, sprint, zotdef")
      lg_error('!lm * game!=cow').should \
          eql("Invalid expression `game!=cow`: " +
              "`game` may only be used with `=`")
    end
  end

  it "should recognise alternative field names" do
    ['job', 'class', 'cls', 'role', 'c'].each do |field|
      query = lg("!lg * #{field}=Hu")
      query.where_clauses_with_parameters.should \
        eql([' WHERE cls=?', ['Hunter']])
    end

    ['race', 'sp', 'species', 'r'].each do |field|
      query = lg("!lg * #{field}=Hu")
      query.where_clauses_with_parameters.should \
        eql([' WHERE race=?', ['Human']])
    end

    ['char', 'ch'].each do |field|
      query = lg("!lg * #{field}=HuHu")
      query.where_clauses_with_parameters.should \
        eql([' WHERE charabbrev=?', ['HuHu']])
    end

    ['score', 'sc'].each do |field|
      query = lg("!lg * #{field}=999")
      query.where_clauses_with_parameters.should \
        eql([' WHERE sc=?', ['999']])
    end

    ['ktype', 'ktyp'].each do |field|
      query = lg("!lg * #{field}=win")
      query.where_clauses_with_parameters.should \
        eql([' WHERE ktyp=?', ['winning']])
    end
  end

  context "given a query with an invalid query context" do
    it "should raise a QueryError noting that the context is invalid" do
      lg_error('!invalid * killer=goblin').should \
          eql("No query context named `invalid`")
    end
  end

  it "should correctly parse an empty field match" do
    lg('!lg * killer=').where_clauses_with_parameters.should \
        eql([' WHERE killer=?', ['']])
    lg('!lg * god= ktyp=win').where_clauses_with_parameters.should \
        eql([' WHERE god=? AND ktyp=?', ['', 'winning']])
  end

  context "given a query with a version as a keyword argument" do
    it "should parse the query successfully" do
      lg('!lg * 0.8')
    end
  end

  context "given keyword arguments" do
    it "should recognise a character abbreviation" do
      lg('!lg * DrFE').where_clauses_with_parameters.should \
          eql([' WHERE charabbrev=?', ['DrFE']])
      lg('!lg * hehe').where_clauses_with_parameters.should \
          eql([' WHERE charabbrev=?', ['hehe']])
    end

    it "should recognise a god abbreviation" do
      lg('!lg * ely').where_clauses_with_parameters.should \
          eql([' WHERE god=?', ['Elyvilon']])
      lg('!lg * nem').where_clauses_with_parameters.should \
          eql([' WHERE god=?', ['Nemelex Xobeh']])
      lg('!lg * tso').where_clauses_with_parameters.should \
          eql([' WHERE god=?', ['The Shining One']])
      lg('!lg * !kiku').where_clauses_with_parameters.should \
          eql([' WHERE god!=?', ['Kikubaaqudgha']])
      lg('!lg * xom').where_clauses_with_parameters.should \
          eql([' WHERE god=?', ['Xom']])
      lg('!lg * god=tso').where_clauses_with_parameters.should \
          eql([' WHERE god=?', ['The Shining One']])
    end
  end

  context "given a query with an action flag" do
    it "should have the correct query action type" do
      lg('!lg * -tv:<3').action_type.should == "tv"
      lg('!lg * -ttyrec').action_type.should == 'ttyrec'
      lg('!lg *').action_type.should be_nil
    end

    it "should extract the full action flag text" do
      lg('!lg * -tv:<2:>3').action_flag.should == "tv:<2:>3"
      lg('!lg * -ttyrec').action_flag.should == "ttyrec"
      lg('!lg * -log').action_flag.should == "log"
      lg('!lg *').action_flag.should be_nil
    end
  end

  context "given a query with an action flag in a subquery" do
    it "should throw a parse error" do
      lg_error('!lg * [[ * -log ]]').should eql("Subquery [[ * -log ]] has an action flag")
    end
  end

  context "given a top-level query with a query mode" do
    it "should throw a parse error" do
      lg_error('!lg !lg *').should eql("Query mode `!lg` not permitted at top-level")
    end
  end

  context "given a subquery with a query mode" do
    it "should parse the subquery just fine" do
      lg('!lg [[ !lm * ]]').subqueries.size.should eql(1)
    end
  end

  context "given a result index" do
    it "should report the correct result index" do
      lg('!lg * 22').result_index.should eql(22)
      lg('!lg * -5').result_index.should eql(-5)
      lg('!lg * killer=goblin -2').result_index.should eql(-2)
      lg('!lg * [[ * -5 ]]').result_index.should be_nil

      lg('!lg * god= -5').result_index.should eql(-5)
      lg('!lg * god=-5').result_index.should eql(nil)
      lg('!lg * god= 2').result_index.should eql(2)
      lg('!lg * god=2').result_index.should eql(nil)

      lg('!lg * god= #-5').result_index.should eql(-5)
      lg('!lg * god= #22').result_index.should eql(22)
      lg('!lg * god=#22').result_index.should be_nil
      lg('!lg * god=#22').where_clauses_with_parameters.should \
          eql([' WHERE god=?', ['#22']])
    end
  end

  context "given too many result indices" do
    it "should throw a parse error" do
      lg_error('!lg * 22 -5').should eql('Too many result indexes in query (extras: -5)')
    end
  end

  context "given a summary query" do
    it "should notice that it is a summary query" do
      lg('!lg * s=killer').summary_query?.should be_true
      lg('!lg * [[ * s=killer ]]').summary_query?.should be_false
    end

    it "should correctly identify the grouped fields" do
      lg('!lg *').summary_grouped_fields.should be_nil
      lg('!lg * s=killer').summary_grouped_fields.should eql(['killer'])
      lg('!lg * s=-killer,lg:place').summary_grouped_fields.should eql(['-killer', 'lg:place'])
      lg('!lg * s=cv%').summary_grouped_fields.should eql(['cv%'])
    end
  end

  context "given a ratio query" do
    it "should notice that it is a ratio query" do
      lg('!lg * s=killer').ratio_query?.should be_false
      lg('!lg * s=char / win').ratio_query?.should be_true
    end

    it "should correctly find the ratio tail" do
      lg('!lg * / win').ratio_tail.text.should eql('win')
    end

    it "should parse the having clause" do
      q = lg('!lg * won crace!=OM|GE|El|Gn|HD s=crace / name=foo ?: N = 0')
      q.ratio_query?.should be_true
      q.ratio_tail.having_clause_node.text.should eql('N = 0')
    end
  end

  context "given a query with conditions" do
    it "should visit each condition node" do
      nodes = lg_collect_text(
                  '!lg * 0.8 717 !win s=name ((killer=rat || killer=goblin))',
                  :each_condition_node)
      nodes.should eql(["*", "0.8", "!win",
                         "killer=rat || killer=goblin",
                         "killer=rat",
                         "killer=goblin"])
    end
  end

  context "given a query with no filter conditions" do
    it "should have no WHERE clause" do
      lg('!lg *').where_clauses.should eql('')
    end
  end

  context "given a query with filter conditions" do
    it "should have a matching WHERE clause" do
      lg('!lg * 0.8').where_clauses_with_parameters.should \
         eql([" WHERE cv=?", ['0.8']])

      lg('!lg elliptic 0.7 !win').where_clauses_with_parameters.should \
         eql([" WHERE pname=? AND cv=? AND ktyp!=?",
              ['elliptic', '0.7', 'winning']])

      lg('!lg * str<5 ktyp=win').where_clauses_with_parameters.should \
         eql([" WHERE sstr<? AND ktyp=?", ['5', 'winning']])
    end
  end

  context "given a nick selector as a keyword argument" do
    it "should generate the correct WHERE clause" do
      lg('!lg * @elliptic').where_clauses_with_parameters.should \
          eql([" WHERE pname=?", ['elliptic']])
    end
  end

  context "given a query needing fixups" do
    it "should apply the killer fixup" do
      lg('!lg * killer=hobgoblin').where_clauses_with_parameters.should \
         eql([" WHERE killer=? OR killer=? OR killer=?",
               ['hobgoblin', 'a hobgoblin', 'an hobgoblin']])
    end

    it "should apply the ktyp fixup" do
      lg('!lg * quit').where_clauses_with_parameters.should \
         eql([' WHERE ktyp=?', ['quitting']])
      lg('!lg * !drowning').where_clauses_with_parameters.should \
         eql([' WHERE ktyp!=?', ['water']])
      lg('!lg * ktyp=win').where_clauses_with_parameters.should \
         eql([' WHERE ktyp=?', ['winning']])
      lg('!lg * ktype=win').where_clauses_with_parameters.should \
         eql([' WHERE ktyp=?', ['winning']])
    end

    it "should apply the place fixup" do
      lg('!lg * orc').where_clauses_with_parameters.should \
         eql([" WHERE place LIKE ?", ['orc:%']])
      lg('!lg * Blade').where_clauses_with_parameters.should \
         eql([" WHERE place=?", ['Blade']])
      lg('!lm * oplace=elf').where_clauses_with_parameters.should \
         eql([" WHERE oplace LIKE ?", ['elf:%']])
      lg('!lm * oplace!=elf').where_clauses_with_parameters.should \
         eql([" WHERE oplace NOT LIKE ?", ['elf:%']])
      lg('!lg * place=temple').where_clauses_with_parameters.should \
         eql([" WHERE place=?", ['temple']])
    end

    it "should apply the race fixup" do
      lg('!lg * Ha').where_clauses_with_parameters.should \
         eql([" WHERE crace=?", ["Halfling"]])
      lg('!lg * HE').where_clauses_with_parameters.should \
         eql([" WHERE crace=?", ["High Elf"]])
      lg('!lg * race=HE').where_clauses_with_parameters.should \
         eql([" WHERE race=?", ["High Elf"]])
      lg('!lg * crace=Dr').where_clauses_with_parameters.should \
         eql([" WHERE crace=?", ["Draconian"]])
      lg('!lg * race=Dr').where_clauses_with_parameters.should \
         eql([" WHERE race LIKE ?", ["%Draconian"]])
      lg('!lg * race!=Dr').where_clauses_with_parameters.should \
         eql([" WHERE race NOT LIKE ?", ["%Draconian"]])
    end

    it "should apply the class fixup" do
      lg('!lg * St').where_clauses_with_parameters.should \
         eql([" WHERE cls=?", ['Stalker']])
      lg('!lg * cls=Hu').where_clauses_with_parameters.should \
         eql([" WHERE cls=?", ['Hunter']])
    end

    it "should apply the race/class fixup for regex matched abbreviations" do
      [ ['cls', 'St|Re|Hu', ['Stalker', 'Reaver', 'Hunter'] ],
        ['crace', 'Hu|Tr|Gh', ['Human', 'Troll', 'Ghoul'] ] ].each do |field, value, matches|

        lg("!lg * #{field}=#{value}").where_clauses_with_parameters.should \
            eql([" WHERE #{field}=? OR #{field}=? OR #{field}=?", matches])

        lg("!lg * #{field}~~#{value}").where_clauses_with_parameters.should \
            eql([" WHERE #{field} REGEXP ?", [value]])

        lg("!lg * #{field}!=#{value}").where_clauses_with_parameters.should \
            eql([" WHERE #{field}!=? AND #{field}!=? AND #{field}!=?", matches])

        lg("!lg * #{field}!~~#{value}").where_clauses_with_parameters.should \
            eql([" WHERE #{field} NOT REGEXP ?", [value]])
      end

      lg('!lg * race=Dr|Tr|SE').where_clauses_with_parameters.should \
          eql([' WHERE race LIKE ? OR race=? OR race=?',
                ['%Draconian', 'Troll', 'Sludge Elf']])
      lg_error('!lg * race=Dr|Wo|SE').should \
          eql("Unknown species `Wo` in `Dr|Wo|SE`")
    end

    it "should throw a parse error given an ambiguous race/class abbreviation" do
      lg_error('!lg * Hu').should eql("Ambiguous keyword `Hu` - may be species or class (crace=Human or cls=Hunter)")
    end
  end

  context "#operators" do
    it "should recognise the = operator" do
      lg('!lg * cv=0.8').where_clauses.should eql(" WHERE cv=?")
    end

    it "should recognise the != operator" do
      lg('!lg * cv!=0.8').where_clauses.should eql(" WHERE cv!=?")
    end

    it "should recognise the == operator" do
      lg('!lg * cv==0.8').where_clauses.should eql(" WHERE cv=?")
    end

    it "should recognise the !== operator" do
      lg('!lg * cv!==0.8').where_clauses.should eql(" WHERE cv!=?")
    end

    it "should recognise the < operator" do
      lg('!lg * cv<0.8').where_clauses.should eql(' WHERE cv<?')
    end

    it "should recognise the <= operator" do
      lg('!lg * cv<=0.8').where_clauses.should eql(' WHERE cv<=?')
    end

    it "should recognise the > operator" do
      lg('!lg * cv>0.8').where_clauses.should eql(' WHERE cv>?')
    end

    it "should recognise the >= operator" do
      lg('!lg * cv>=0.8').where_clauses.should eql(' WHERE cv>=?')
    end

    it "should recognise the =~ operator" do
      lg('!lg * killer=~goblin').where_clauses_with_parameters.should \
          eql([" WHERE killer LIKE ?", ['%goblin%']])
      lg('!lg * killer=~*goblin').where_clauses_with_parameters.should \
          eql([" WHERE killer LIKE ?", ['%goblin']])
      lg('!lg * killer=~*goblin?').where_clauses_with_parameters.should \
          eql([" WHERE killer LIKE ?", ['%goblin_']])
      lg('!lg * killer=~goblin*').where_clauses_with_parameters.should \
          eql([" WHERE killer LIKE ?", ['goblin%']])
      lg('!lg * killer=~goblin?').where_clauses_with_parameters.should \
          eql([" WHERE killer LIKE ?", ['goblin_']])
    end

    it "should recognise the !~ operator" do
      lg('!lg * killer!~goblin').where_clauses_with_parameters.should \
          eql([" WHERE killer NOT LIKE ?", ['%goblin%']])
      lg('!lg * killer!~*goblin').where_clauses_with_parameters.should \
          eql([" WHERE killer NOT LIKE ?", ['%goblin']])
      lg('!lg * killer!~*goblin?').where_clauses_with_parameters.should \
          eql([" WHERE killer NOT LIKE ?", ['%goblin_']])
      lg('!lg * killer!~goblin*').where_clauses_with_parameters.should \
          eql([" WHERE killer NOT LIKE ?", ['goblin%']])
      lg('!lg * killer!~goblin?').where_clauses_with_parameters.should \
          eql([" WHERE killer NOT LIKE ?", ['goblin_']])
    end

    it "should recognise the ~~ operator" do
      lg('!lg * killer~~goblin').where_clauses.should \
          eql(' WHERE killer REGEXP ?')
    end

    it "should recognise the !~~ operator" do
      lg('!lg * killer!~~goblin').where_clauses.should \
          eql(' WHERE killer NOT REGEXP ?')
    end

    it "should convert = to ~~ if there are regex metacharacters" do
      lg('!lg * killer=goblin|Xtahua').where_clauses_with_parameters.should \
          eql([' WHERE killer REGEXP ?', ['goblin|Xtahua']])
    end

    it "should convert != to !~~ if there are regex metacharacters" do
      lg('!lg * killer!=goblin|Xtahua').where_clauses_with_parameters.should \
          eql([' WHERE killer NOT REGEXP ?', ['goblin|Xtahua']])
    end
  end
end