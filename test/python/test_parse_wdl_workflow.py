#!/usr/bin/env python3

import unittest
from unittest.mock import patch
import sys
from io import StringIO
import asyncio
import json

import WDL

from scripts import parse_wdl_workflow

# Test cases


class TestReadAndParseInput(unittest.TestCase):
    def test_read_stdin_result_type(self):
        with patch("sys.stdin", StringIO(test_wdl)):
            result = asyncio.run(parse_wdl_workflow.read_stdin("stdin", "", ""))
            self.assertIsInstance(result, WDL.ReadSourceResult)
            self.assertEqual(result.source_text, test_wdl)
            self.assertEqual(result.abspath, "stdin")

    def test_read_stdin_result_parsing(self):
        with patch("sys.stdin", StringIO(test_wdl)):
            doc = WDL.load("stdin", read_source=parse_wdl_workflow.read_stdin)
            assert doc.workflow
            self.assertEqual(len(doc.tasks), 3)
            self.assertEqual(len(doc.workflow.inputs), 4)
            self.assertEqual(len(doc.workflow.body), 4)
            self.assertIsInstance(doc.workflow.body[0], WDL.Tree.Call)
            self.assertIsInstance(doc.workflow.body[1], WDL.Tree.Conditional)
            self.assertIsInstance(doc.workflow.body[2], WDL.Tree.Decl)


class TestJSONOutput(unittest.TestCase):
    def setUp(self):
        with patch("sys.stdin", StringIO(test_wdl)), patch("sys.stdout", new_callable=StringIO):
            parse_wdl_workflow.main()
            output = sys.stdout.getvalue()
            self.json = json.loads(output)
            self.task_names = frozenset(["RunValidateInput", "RunBowtie2_bowtie2_human_out", "RunGsnapFilter"])
            self.workflow_inputs = ["docker_image_id", "fastqs_0", "fastqs_1", "host_genome"]

    def test_workflow_inputs(self):
        input_types = ["String", "File", "File", "String"]
        json_inputs = self.json["inputs"]
        self.assertEqual(len(json_inputs), 4)
        for var, var_type in zip(self.workflow_inputs, input_types):
            self.assertIn(var, json_inputs)
            json_type = json_inputs[var]
            self.assertEqual(var_type, json_type)

    def test_task_names(self):
        for task in self.json["task_names"]:
            self.assertIn(task, self.task_names)

    def test_task_info(self):
        # Make sure inputs not from previous tasks have the WorkflowInput prefix
        task_info = self.json["task_inputs"]
        run_validate_inputs = task_info["RunValidateInput"]
        for prefixed_var in run_validate_inputs:
            self.assertIn(".", prefixed_var)
            prefix, var = prefixed_var.split(".")
            self.assertEqual(prefix, "WorkflowInput")
            self.assertIn(var, self.workflow_inputs)
        # Test the rest of the inputs - either they're in the stage input,
        # or one of the outputs
        valid_prefixes = set(["WorkflowInput"]).union(self.task_names)
        valid_outputs = self.json["outputs"].values()
        for task_name, task_inputs in task_info.items():
            self.assertIn(task_name, self.task_names)
            for prefixed_var in task_inputs:
                self.assertIn(".", prefixed_var)
                prefix, var = prefixed_var.split(".")
                self.assertIn(prefix, valid_prefixes)
                if prefix == "WorkflowInput":
                    self.assertIn(var, self.workflow_inputs)
                else:
                    self.assertIn(prefixed_var, valid_outputs)

    def test_file_basenames_and_outputs(self):
        basenames = self.json["basenames"]
        valid_outputs = self.json["outputs"].values()
        self.assertEqual(len(basenames), len(valid_outputs))
        for key, value in basenames.items():
            self.assertIn(key, valid_outputs)
            self.assertIn(".", key)
            self.assertIn(".", value)
            task = key.split(".")[0]
            self.assertNotIn(task, value)


class TestWDL11Parsing(unittest.TestCase):
    """WDL 1.1 coverage: version 1.1 parsing, WDL.Expr.Null (None) handling,
    None-guarded workflow inputs/outputs, and the WorkflowInput. prefix applied to
    declarations that reference workflow inputs. miniwdl was bumped to 1.14.2
    (WDL 1.1 capable) but this parser previously had no 1.1 / Null coverage."""

    def _parse(self, wdl_text):
        with patch("sys.stdin", StringIO(wdl_text)), patch("sys.stdout", new_callable=StringIO):
            parse_wdl_workflow.main()
            return json.loads(sys.stdout.getvalue())

    def test_version_1_1_parses(self):
        with patch("sys.stdin", StringIO(test_wdl_1_1)):
            doc = WDL.load("stdin", read_source=parse_wdl_workflow.read_stdin)
            assert doc.workflow
            self.assertEqual(doc.workflow.name, "wdl_1_1_example")

    def test_null_input_is_ignored(self):
        # optional_ref = None parses to WDL.Expr.Null; it must be ignored, not raise.
        process_inputs = self._parse(test_wdl_1_1)["task_inputs"]["ProcessSample"]
        self.assertNotIn("WorkflowInput.optional_ref", process_inputs)
        for prefixed_var in process_inputs:
            # Every input is a well-formed two-component "Prefix.var" reference.
            self.assertEqual(len(prefixed_var.split(".")), 2)

    def test_declaration_referencing_workflow_inputs_is_prefixed(self):
        # selected_fastq is a declaration resolving to bare workflow inputs; after
        # expansion each must carry the WorkflowInput. prefix, and no phantom
        # WorkflowInput.selected_fastq (the declaration name) should remain.
        process_inputs = self._parse(test_wdl_1_1)["task_inputs"]["ProcessSample"]
        self.assertNotIn("WorkflowInput.selected_fastq", process_inputs)
        self.assertIn("WorkflowInput.input_fastq", process_inputs)
        self.assertIn("WorkflowInput.alt_fastq", process_inputs)

    def test_none_inputs_and_outputs_are_guarded(self):
        # A workflow with no input/output blocks yields None for inputs/outputs in
        # WDL 1.1; the parser must treat them as empty rather than crash.
        parsed = self._parse(test_wdl_1_1_no_io)
        self.assertEqual(parsed["inputs"], {})
        self.assertEqual(parsed["outputs"], {})
        self.assertEqual(parsed["task_names"], ["NoOp"])


class TestFailFast(unittest.TestCase):
    """The parser fails fast on genuinely unsupported constructs rather than
    silently returning None or an empty result."""

    def test_parse_input_item_unsupported_raises(self):
        with self.assertRaises(Exception):
            parse_wdl_workflow.parse_input_item(object())

    def test_parse_workflow_task_unsupported_raises(self):
        with self.assertRaises(Exception):
            parse_wdl_workflow.parse_workflow_task(object())


# Test document

test_wdl = """
version 1.0
task RunValidateInput {
  input {
    String docker_image_id
    Array[File] fastqs
    String host_genome
  }
  command<<<
  idseq-dag-run-step --workflow-name host_filter \
    --step-module idseq_dag.steps.run_validate_input \
    --step-class PipelineStepRunValidateInput \
  >>>
  output {
    File validate_input_summary_json = "validate_input_summary.json"
    File valid_input1_fastq = "valid_input1.fastq"
    File? valid_input2_fastq = "valid_input2.fastq"
    File? output_read_count = "validate_input_out.count"
    File? input_read_count = "fastqs.count"
  }
  runtime {
    docker: docker_image_id
  }
}
task RunBowtie2_bowtie2_human_out {
  input {
    String docker_image_id
    Array[File] unmapped_human_fa
  }
  command<<<
  idseq-dag-run-step --workflow-name host_filter \
    --step-module idseq_dag.steps.run_bowtie2 \
    --step-class PipelineStepRunBowtie2 \
  >>>
  output {
    File bowtie2_human_1_fa = "bowtie2_human_1.fa"
    File? bowtie2_human_2_fa = "bowtie2_human_2.fa"
    File? bowtie2_human_merged_fa = "bowtie2_human_merged.fa"
    File? output_read_count = "bowtie2_human_out.count"
  }
  runtime {
    docker: docker_image_id
  }
}
task RunGsnapFilter {
  input {
    String docker_image_id
    Array[File] subsampled_fa
  }
  command<<<
  idseq-dag-run-step --workflow-name host_filter \
    --step-module idseq_dag.steps.run_gsnap_filter \
    --step-class PipelineStepRunGsnapFilter \
  >>>
  output {
    File gsnap_filter_1_fa = "gsnap_filter_1.fa"
    File? gsnap_filter_2_fa = "gsnap_filter_2.fa"
    File? gsnap_filter_merged_fa = "gsnap_filter_merged.fa"
    File? output_read_count = "gsnap_filter_out.count"
  }
  runtime {
    docker: docker_image_id
  }
}
workflow idseq_host_filter {
  input {
    String docker_image_id
    File fastqs_0
    File? fastqs_1
    String host_genome
  }
  call RunValidateInput {
    input:
      docker_image_id = docker_image_id,
      fastqs = select_all([fastqs_0, fastqs_1]),
      host_genome = host_genome,
  }
  if (host_genome != "human") {
    call RunBowtie2_bowtie2_human_out {
      input:
        docker_image_id = docker_image_id,
        unmapped_human_fa = select_all([RunValidateInput.valid_input1_fastq, RunValidateInput.valid_input2_fastq]),
    }
  }
  Array[File] gsnap_filter_input = if (host_genome == "human")
    then select_all([RunValidateInput.valid_input1_fastq, RunValidateInput.valid_input2_fastq])
    else select_all([RunBowtie2_bowtie2_human_out.bowtie2_human_1_fa, RunBowtie2_bowtie2_human_out.bowtie2_human_2_fa, RunBowtie2_bowtie2_human_out.bowtie2_human_merged_fa])
  call RunGsnapFilter {
    input:
      docker_image_id = docker_image_id,
      subsampled_fa = gsnap_filter_input,
  }
  output {
    File validate_input_out_validate_input_summary_json = RunValidateInput.validate_input_summary_json
    File validate_input_out_valid_input1_fastq = RunValidateInput.valid_input1_fastq
    File? validate_input_out_valid_input2_fastq = RunValidateInput.valid_input2_fastq
    File? validate_input_out_count = RunValidateInput.output_read_count
    File? bowtie2_human_out_bowtie2_human_1_fa = RunBowtie2_bowtie2_human_out.bowtie2_human_1_fa
    File? bowtie2_human_out_bowtie2_human_2_fa = RunBowtie2_bowtie2_human_out.bowtie2_human_2_fa
    File? bowtie2_human_out_bowtie2_human_merged_fa = RunBowtie2_bowtie2_human_out.bowtie2_human_merged_fa
    File? bowtie2_human_out_count = RunBowtie2_bowtie2_human_out.output_read_count
    File gsnap_filter_out_gsnap_filter_1_fa = RunGsnapFilter.gsnap_filter_1_fa
    File? gsnap_filter_out_gsnap_filter_2_fa = RunGsnapFilter.gsnap_filter_2_fa
    File? gsnap_filter_out_gsnap_filter_merged_fa = RunGsnapFilter.gsnap_filter_merged_fa
    File? gsnap_filter_out_count = RunGsnapFilter.output_read_count
    File? input_read_count = RunValidateInput.input_read_count
  }
}
"""  # noqa


# WDL 1.1 document. Exercises: version 1.1 parsing, a None-valued optional call
# input (WDL.Expr.Null), and a declaration (selected_fastq) that references
# workflow inputs so its expansion must gain the WorkflowInput. prefix.
test_wdl_1_1 = """
version 1.1
task ProcessSample {
  input {
    String docker_image_id
    File sample
    File? optional_ref
  }
  command <<<
  echo processing
  >>>
  output {
    File processed = "processed.fa"
    File? maybe_out = "maybe.fa"
  }
  runtime {
    docker: docker_image_id
  }
}
workflow wdl_1_1_example {
  input {
    String docker_image_id
    File input_fastq
    File? alt_fastq
    Boolean use_alt = false
  }
  File selected_fastq = if use_alt
    then select_first([alt_fastq, input_fastq])
    else input_fastq
  call ProcessSample {
    input:
      docker_image_id = docker_image_id,
      sample = selected_fastq,
      optional_ref = None,
  }
  output {
    File processed_out = ProcessSample.processed
    File? maybe_out = ProcessSample.maybe_out
  }
}
"""  # noqa


# WDL 1.1 workflow with no input/output blocks. In 1.1 doc.workflow.inputs and
# doc.workflow.outputs come back as None here, exercising the "or []" guards.
test_wdl_1_1_no_io = """
version 1.1
task NoOp {
  input {
    String docker_image_id
  }
  command <<<
  echo hi
  >>>
  output {
    File result = "result.txt"
  }
  runtime {
    docker: docker_image_id
  }
}
workflow no_inputs_outputs {
  call NoOp {
    input:
      docker_image_id = "img",
  }
}
"""  # noqa
