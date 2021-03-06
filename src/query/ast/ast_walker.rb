require 'set'

module Query
  module AST
    class ASTWalker
      @@debugging = false
      def self.debugging
        old_debug = @debugging
        begin
          @@debugging = true
          yield
        ensure
          @@debugging = old_debug
        end
      end

      def self.debugging?
        @@debugging
      end

      def self.block_call(block, node, parent)
        block.call(node, parent)
      end

      def self.map_nodes(ast, parent=nil, condition=nil, &block)
        return nil if ast.nil?
        debug{"map_nodes: #{ast}: #{ast.class}"} if debugging?
        ast.arguments = ast.arguments.map { |arg|
          map_nodes(arg, ast, condition, &block)
        }.compact
        debug{ "Post-map: #{ast}"} if debugging?
        if !condition || condition.call(ast)
          debug{ "Self-call: #{ast}"} if debugging?
          return block_call(block, ast, parent)
        end
        ast
      end

      def self.each_node(ast, parent=nil, condition=nil, &block)
        return nil if ast.nil?
        ast.arguments.each { |arg|
          each_node(arg, ast, condition, &block)
        }
        if !condition || condition.call(ast)
          return block_call(block, ast, parent)
        end
        ast
      end

      def self.find(ast, &block)
        ast.arguments.each { |arg|
          result = find(arg, &block)
          return result if result
        }
        block.call(ast)
      end

      def self.map_predicates(ast, &block)
        map_nodes(ast, nil, Proc.new { |node| node.type.boolean? }, &block)
      end

      def self.map_kinds(ast, kinds, &block)
        kinds = Set.new([kinds]) unless kinds.is_a?(Set)
        map_nodes(ast, nil, Proc.new { |node| kinds.include?(node.kind) }, &block)
      end

      def self.each_kind(ast, kinds, &block)
        kinds = Set.new([kinds]) unless kinds.is_a?(Set)
        each_node(ast, nil, Proc.new { |node| kinds.include?(node.kind) }, &block)
      end

      def self.map_fields(ast, &block)
        map_kinds(ast, :field, &block)
      end

      def self.map_raw_fields(ast, &block)
        map_kinds(ast, :raw_field, &block)
      end

      def self.each_field(ast, &block)
        each_kind(ast, :field, &block)
      end

      def self.map_keywords(ast, &block)
        map_kinds(ast, :keyword, &block)
      end

      def self.map_values(ast, &block)
        map_kinds(ast, :value, &block)
      end
    end
  end
end
