# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class Agent < Core::Executors::Base
          MAX_TOOL_ITERATIONS = 10

          def call(state)
            @current_state = state

            agent_id = config.agent_id
            agent = Extension.agents(workflow(state))[agent_id]
            raise ExecutionError, "Agent not found: #{agent_id}" unless agent

            prompt = resolve(state, config.prompt)
            tool_classes = build_tool_classes(state, agent)

            response = run_agent_loop(state, agent, prompt, tool_classes)

            state = @current_state
            content = response.content.respond_to?(:text) ? response.content.text : response.content.to_s
            state = store(state, config.output, content)
            continue(state, output: content)
          end

          private

          def workflow(state)
            DurableWorkflow.registry[state.workflow_id]
          end

          def build_chat(agent)
            AI.chat(model: agent.model)
          end

          def build_tool_classes(_state, agent)
            return [] if agent.tools.empty? && agent.handoffs.empty?

            tool_classes = []

            # Get RubyLLM::Tool classes from registry
            agent.tools.each do |tool_id|
              tool_class = ToolRegistry[tool_id]
              tool_classes << tool_class if tool_class
            end

            # Create handoff tools
            agent.handoffs.each do |handoff|
              tool_classes << build_handoff_tool(handoff)
            end

            tool_classes
          end

          def build_handoff_tool(handoff)
            target_agent_id = handoff.agent_id
            tool_description = handoff.description || "Transfer to #{target_agent_id}"
            executor_ref = self
            tool_name = "transfer_to_#{target_agent_id}"

            # Create named handoff tool class
            class_name = "TransferTo#{target_agent_id.split('_').map(&:capitalize).join}"
            return GeneratedTools.const_get(class_name) if GeneratedTools.const_defined?(class_name)

            GeneratedTools.const_set(class_name, Class.new(RubyLLM::Tool) do
              description tool_description

              # Override name to avoid long namespace in tool name
              define_method(:name) { tool_name }

              define_method(:execute) do
                executor_ref.instance_variable_get(:@current_state).tap do
                  new_state = executor_ref.instance_variable_get(:@current_state)
                                         .with_ctx(_handoff_to: target_agent_id)
                  executor_ref.instance_variable_set(:@current_state, new_state)
                end
                "Transferring to #{target_agent_id}"
              end
            end)
          end

          def run_agent_loop(state, agent, prompt, tool_classes)
            iterations = 0
            chat = build_chat(agent)

            # Add tools to chat
            tool_classes.each { |tc| chat.with_tool(tc) }

            # Build full prompt with system instructions
            full_prompt = if agent.instructions
                            "System: #{agent.instructions}\n\nUser: #{prompt}"
                          else
                            prompt
                          end

            # Main agent loop
            loop do
              iterations += 1
              raise ExecutionError, "Agent exceeded max iterations (#{MAX_TOOL_ITERATIONS})" if iterations > MAX_TOOL_ITERATIONS

              response = chat.ask(full_prompt)

              # If no tool calls, we're done
              return response unless response.tool_call?

              # Execute tool calls and continue
              response.tool_calls.each do |tool_call|
                tool_name = begin
                  tool_call.name
                rescue StandardError
                  Utils.fetch(tool_call, :name)
                end
                arguments = begin
                  tool_call.arguments
                rescue StandardError
                  (Utils.fetch(tool_call, :arguments) || {})
                end

                result = execute_tool_call(state, tool_name, arguments)
                full_prompt = "Tool #{tool_name} returned: #{result}"
              end
            end
          end

          def execute_tool_call(_state, tool_name, arguments)
            # Check for handoff tools
            if tool_name.start_with?('transfer_to_') || tool_name.match?(/^TransferTo/)
              target_agent = tool_name.sub(/^transfer_to_/, '').sub(/^TransferTo/, '')
                                      .gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
              @current_state = @current_state.with_ctx(_handoff_to: target_agent)
              return "Transferring to #{target_agent}"
            end

            # Execute via ToolRegistry
            tool_class = ToolRegistry[tool_name]
            raise ExecutionError, "Tool not found: #{tool_name}" unless tool_class

            tool_instance = tool_class.new
            args = arguments.is_a?(Hash) ? arguments.transform_keys(&:to_sym) : {}
            tool_instance.call(**args)
          rescue StandardError => e
            "Error: #{e.message}"
          end
        end
      end
    end
  end
end
