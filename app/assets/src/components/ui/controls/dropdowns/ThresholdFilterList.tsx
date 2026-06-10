import React from "react";
import {
  MetricOption,
  ThresholdFilterData,
  ThresholdFilterOperator,
} from "~/interface/dropdown";
import { ThresholdFilter } from "~ui/controls/dropdowns";
import cs from "./threshold_filter_list.scss";

interface ThresholdFilterListProps {
  metrics: MetricOption[];
  operators: ThresholdFilterOperator[];
  thresholds: ThresholdFilterData[];
  onChangeThreshold: (
    thresholdIdx: number,
    threshold: ThresholdFilterData,
  ) => void;
  onRemoveThreshold: (thresholdIdx: number) => void;
  onAddThreshold: () => void;
}

const ThresholdFilterList = ({
  metrics,
  operators,
  thresholds,
  onChangeThreshold,
  onRemoveThreshold,
  onAddThreshold,
}: ThresholdFilterListProps) => {
  return (
    <div className={cs.thresholdFilterList}>
      <div className={cs.thresholdFilterGrid}>
        {Array.isArray(thresholds) &&
          thresholds.map((threshold: ThresholdFilterData, idx: number) => (
            <ThresholdFilter
              key={`${threshold.metric}-${idx}`}
              metrics={metrics}
              operators={operators}
              threshold={threshold}
              onChange={(threshold: ThresholdFilterData) => {
                onChangeThreshold(idx, threshold);
              }}
              onRemove={() => {
                onRemoveThreshold(idx);
              }}
            />
          ))}
        <div className={cs.addThresholdRow}>
          <div className={cs.addThresholdColumn}>
            <span
              data-testid="add-threshold"
              className={cs.addThresholdLink}
              onClick={() => {
                onAddThreshold();
              }}
              role="button"
              onKeyDown={e => {
                if (e.key === "Enter") {
                  onAddThreshold();
                }
              }}
              tabIndex={0}
            >
              + ADD THRESHOLD
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ThresholdFilterList;
